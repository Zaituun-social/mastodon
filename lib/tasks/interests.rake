# frozen_string_literal: true

# One-off maintenance: reassign a curated set of hashtags to local root statuses.
#
# Input MAP is JSON, a list of { "question_id": "<status id>", "tags": ["tag", ...] }
# (a { "<id>": ["tag", ...] } object is also accepted).
#
# For each local, non-reblog, non-reply status: the trailing hashtag-only block is
# stripped from the text and replaced with the curated "#tag"s. statuses_tags is then
# re-derived from the new text (via ProcessHashtagsService), featured_tags counts are
# corrected, the fan-out cache is busted, and Elasticsearch is reindexed. No edit
# marker is set (edited_at stays nil) and nothing is federated.
#
# Statuses are skipped and reported, never written, when they are remote, reblogs,
# replies, have blank text, or still contain a hashtag in the body after the trailing
# block is stripped ("leftover" — an inline tag or a non "\n\n" separator).
#
#   bin/rails interests:retag MAP=curated_tags.json DRY=1   # dry-run, prints diffs
#   bin/rails interests:retag MAP=curated_tags.json         # apply

module CuratedRetag
  module_function

  TAG_BLOCK_RE = /\A(?:\s*#\S+)+\s*\z/ # trailing segment: hashtags + whitespace only

  def load_map(path)
    raw  = JSON.parse(File.read(path))
    rows = raw.is_a?(Array) ? raw : raw.map { |k, v| { 'question_id' => k, 'tags' => v } }
    map  = Hash.new { |h, k| h[k] = [] }
    rows.each { |r| map[r['question_id'].to_i].concat(Array(r['tags']).filter_map { |t| sanitize_tag(t) }) }
    map.transform_values(&:uniq)
  end

  # space -> underscore (matches existing convention), strip anything Mastodon rejects, then validate.
  def sanitize_tag(raw)
    t = raw.to_s.strip.delete_prefix('#').gsub(/\s+/, '_').gsub(Tag::HASHTAG_INVALID_CHARS_RE, '')
    t.match?(Tag::HASHTAG_NAME_RE) ? t : nil
  end

  def normalize_newlines(text)
    text.to_s.gsub("\r\n", "\n").tr("\r", "\n")
  end

  def strip_tag_block(text)
    return '' if text.match?(TAG_BLOCK_RE) # whole status is just a tag block (no body)

    idx = text.rindex("\n\n")
    return text.rstrip if idx.nil?

    head = text[0...idx]
    tail = text[(idx + 2)..] || ''
    tail.match?(TAG_BLOCK_RE) ? head.rstrip : text.rstrip
  end

  def compose(body, tag_names)
    b = body.strip
    tags = tag_names.map { |t| "##{t}" }
    return b if tags.empty?

    b.empty? ? tags.join(' ') : "#{b}\n\n#{tags.join(' ')}"
  end

  def run(map_path, dry:, sample:)
    map = load_map(map_path)
    ids = map.keys
    puts "loaded #{ids.size} questions from #{map_path}  (DRY=#{dry})"
    no_tag = map.select { |_, v| v.empty? }.keys
    puts "!! #{no_tag.size} rows have no valid tag after sanitize: #{no_tag.first(20).inspect}" if no_tag.any?

    Chewy.strategy(:urgent) unless dry # rake context has no index strategy; sync ES writes on apply

    counters = Hash.new { |h, k| h[k] = [] }
    errors   = []
    printed  = 0

    counters[:missing] = ids - Status.where(id: ids).pluck(:id)

    Status.where(id: ids).find_each(batch_size: 200) do |status|
      raw_tags = map[status.id]
      next if raw_tags.empty?

      result = outcome_for(status, raw_tags)

      if result.is_a?(Symbol) # skip reason or :unchanged
        counters[result] << status.id
      elsif dry
        printed = preview(status, result, printed, sample)
        counters[:changed] << status.id
      else
        apply_change(status, result, counters, errors)
      end
    end

    report(counters, errors)
    finalize(counters[:changed], dry)
  end

  # Returns a skip-reason/:unchanged Symbol, or the composed new text (String) for a change.
  def outcome_for(status, raw_tags)
    return :nonlocal unless status.local?
    return :reblog if status.reblog?
    return :reply if status.in_reply_to_id
    return :blank if status.text.blank?

    body = strip_tag_block(normalize_newlines(status.text))
    return :leftover if Extractor.extract_hashtags(body).present? # inline tag / non "\n\n" separator

    new_text = compose(body, raw_tags)
    new_text == status.text ? :unchanged : new_text
  end

  def preview(status, new_text, printed, sample)
    return printed unless sample.zero? || printed < sample

    puts "\n--- ##{status.id} ---\nOLD: #{status.text.inspect}\nNEW: #{new_text.inspect}"
    printed + 1
  end

  def apply_change(status, new_text, counters, errors)
    ApplicationRecord.transaction do
      status.text = new_text
      status.save!
      ProcessHashtagsService.new.call(status)
    end
    Rails.cache.delete("fan-out/#{status.id}")
    counters[:changed] << status.id
  rescue => e
    errors << [status.id, e.class.name, e.message]
  end

  def finalize(changed_ids, dry)
    if dry
      puts "\nDRY run — nothing written. Review 'leftover' + 'nonlocal' + 'reply' lists before applying."
    elsif Chewy.enabled?
      changed_ids.each_slice(500) do |slice|
        scope = Status.where(id: slice)
        StatusesIndex.import(scope)
        PublicStatusesIndex.import(scope)
      end
      puts "ES reindexed #{changed_ids.size} statuses"
    else
      puts 'ES disabled — no reindex'
    end
  end

  def report(counters, errors)
    puts "\nsummary:"
    %i(changed unchanged missing nonlocal reblog reply blank leftover).each do |k|
      puts "  #{k.to_s.ljust(9)} #{counters[k].size}"
    end
    puts "  errors    #{errors.size}"
    %i(missing nonlocal reblog reply blank leftover).each do |k|
      puts "  #{k}: #{counters[k].first(50).inspect}" if counters[k].any?
    end
    errors.first(50).each { |id, kl, m| puts "ERROR ##{id}: #{kl}: #{m}" }
  end
end

namespace :interests do
  desc 'Reassign curated hashtags to local root statuses (MAP=path.json [DRY=1] [SAMPLE=n])'
  task retag: :environment do
    map_path = ENV.fetch('MAP')
    dry      = ENV['DRY'] == '1'
    sample   = (ENV['SAMPLE'] || (dry ? '20' : '0')).to_i
    CuratedRetag.run(map_path, dry: dry, sample: sample)
  end
end
