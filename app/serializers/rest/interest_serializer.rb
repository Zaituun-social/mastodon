# frozen_string_literal: true

class REST::InterestSerializer < ActiveModel::Serializer
  attributes :id, :name, :tags_count, :last_status_at

  def id
    object.id.to_s
  end

  def tags_count
    presenter.tags_count(object.id)
  end

  def last_status_at
    presenter.last_status_at(object.id)&.iso8601
  end

  private

  def presenter
    instance_options[:presenter]
  end
end
