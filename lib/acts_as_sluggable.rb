require 'active_record'

module ActsAsSluggable
  def self.defaults
    @defaults ||= {
      :source_column => 'name',
      :slug_column => 'slug',
      :scope => "1 = 1",
      :slug_length => 50
    }
  end

  def self.slug(str, options = {})
    options[:length] ||= 50

    #normalize chars to ascii
    str.mb_chars.normalize(:kd).gsub(/[^\x00-\x7F]/, '').to_s.downcase.
      #strip out common punctuation
      gsub(/[\'\"\#\$\,\.\!\?\%\@\(\)]+/, '').
      #replace ampersand chars with 'and'
      gsub(/&/, 'and').
      #replace non-word chars with dashes
      gsub(/[\W^-_]+/, '-').
      #remove double dashes
      gsub(/\-{2}/, '-').
      #removing leading dashes
      gsub(/^-/, '').
      #truncate to a decent length
      slice(0...options[:length]).
      #remove trailing dashes and whitespace
      gsub(/[-\s]*$/, '')
  end

  # Generates a URL slug based on provided fields and adds <tt>after_validation</tt> callbacks.
  #
  #   class Page < ActiveRecord::Base
  #     acts_as_sluggable :source_column => :title, :slug_column => :slug, :scope => :parent
  #   end
  #
  # Configuration options:
  # * <tt>source_column</tt> - specifies the column name used to generate the URL slug
  # * <tt>slug_column</tt> - specifies the column name used to store the URL slug
  # * <tt>scope</tt> - Given a symbol, it'll attach "_id" and use that as the foreign key
  #   restriction. It's also possible to give it an entire string that is interpolated if
  #   you need a tighter scope than just a foreign key.
  # * <tt>slug_length</tt> - specifies a maximum length for slugs, before any unique suffix is added.
  def acts_as_sluggable(options = {})
    configuration = ActsAsSluggable.defaults.merge(options)
    configuration[:scope] = "#{configuration[:scope]}_id".intern if configuration[:scope].is_a?(Symbol) && configuration[:scope].to_s !~ /_id$/

    define_method(:acts_as_sluggable_config) do
      configuration
    end

    include ActsAsSluggable::InstanceMethods

    after_validation :create_slug
  end

  module InstanceMethods
    def source_column
      acts_as_sluggable_config[:source_column]
    end

    def slug_column
      acts_as_sluggable_config[:slug_column]
    end

    def slug_length
      acts_as_sluggable_config[:slug_length]
    end

    def slug_scope_condition
      scope = acts_as_sluggable_config[:scope]

      if scope.is_a?(Symbol)
        {scope => send(scope)}
      else
        scope
      end
    end

    private

      def create_slug
        return if self.errors.size > 0
        return if self[source_column].blank?
        return if self[slug_column].to_s.present?

        proposed_slug = ActsAsSluggable.slug(self[source_column], :length => slug_length)

        suffix = ""
        existing = true
        transaction do
          while existing != nil
            # look for records with the same url slug and increment a counter until we find a unique slug
            existing = self.class.
              where(slug_column => proposed_slug + suffix).
              where(slug_scope_condition).first
            if existing
              suffix = suffix.empty? ? "-0" : suffix.succ
            end
          end
        end
        self[slug_column] = proposed_slug + suffix
      end
    end
  end
end

::ActiveRecord::Base.send :extend, ActsAsSluggable
