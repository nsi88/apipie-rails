module Apipie

  # method field description

  class FieldDescription

    attr_reader :method_description, :name, :desc, :allow_nil, :validator, :options, :metadata, :show, :as
    attr_accessor :parent, :required

    def self.from_dsl_data(method_description, args)
      field_name, validator, desc_or_options, options, block = args
      Apipie::FieldDescription.new(method_description,
                                   field_name,
                                   validator,
                                   desc_or_options,
                                   options,
                                   &block)
    end

    def initialize(method_description, name, validator, desc_or_options = nil, options = {}, &block)

      if desc_or_options.is_a?(Hash)
        options = options.merge(desc_or_options)
      elsif desc_or_options.is_a?(String)
        options[:desc] = desc_or_options
      elsif !desc_or_options.nil?
        raise ArgumentError.new("Field description: expected description or options as 3rd Fieldeter")
      end

      options.symbolize_keys!

      @options = options
      if @options[:field_group]
        @from_concern = @options[:field_group][:from_concern]
      end

      @method_description = method_description
      @name = concern_subst(name)
      @as = options[:as] || @name
      @desc = preformat_text(@options[:desc])

      @parent = @options[:parent]
      @metadata = @options[:meta]

      @required = if @options.has_key? :required
        @options[:required]
      else
        Apipie.configuration.required_by_default?
      end

      @show = if @options.has_key? :show
        @options[:show]
      else
        true
      end

      @allow_nil = @options[:allow_nil] || false

      action_awareness

      if validator
        @validator = Validator::BaseValidator.find(self, validator, @options, block)
        raise "Validator for #{validator} not found." unless @validator
      end
    end

    def from_concern?
      method_description.from_concern? || @from_concern
    end

    def validate(value)
      return true if @allow_nil && value.nil?
      if (!@allow_nil && value.nil?) || !@validator.valid?(value)
        error = @validator.error
        error = ParamError.new(error) unless error.is_a? StandardError
        raise error
      end
    end

    def process_value(value)
      if @validator.respond_to?(:process_value)
        @validator.process_value(value)
      else
        value
      end
    end

    def full_name
      name_parts = parents_and_self.map{|p| p.name if p.show}.compact
      return name.to_s if name_parts.blank?
      return ([name_parts.first] + name_parts[1..-1].map { |n| "[#{n}]" }).join("")
    end


    def parents_and_self
      ret = []
      if self.parent
        ret.concat(self.parent.parents_and_self)
      end
      ret << self
      ret
    end

    def to_json(lang = nil)
      hash = { :name => name.to_s,
               :full_name => full_name,
               :description => preformat_text(Apipie.app.translate(@options[:desc], lang)),
               :required => required,
               :allow_nil => allow_nil,
               :validator => validator.to_s,
               :expected_type => validator.expected_type,
               :metadata => metadata,
               :show => show }
      if sub_fields = validator.fields_ordered
        hash[:fields] = sub_fields.map { |p| p.to_json(lang)}
      end
      hash
    end

    def merge_with(other_field_desc)
      if self.validator && other_field_desc.validator
        self.validator.merge_with(other_field_desc.validator)
      else
        self.validator ||= other_field_desc.validator
      end
      self
    end

    # merge field descripsiont. 
    def self.unify(fields)
      ordering = fields.map(&:name)
      fields.group_by(&:name).map do |name, field_descs|
        field_descs.reduce(&:merge_with)
      end.sort_by { |field| ordering.index(field.name) }
    end

    def action_aware?
      if @options.has_key?(:action_aware)
        return @options[:action_aware]
      elsif @parent
        @parent.action_aware?
      else
        false
      end
    end

    def as_action
      if @options[:field_group] && @options[:field_group][:options] &&
          @options[:field_group][:options][:as]
        @options[:field_group][:options][:as].to_s
      elsif @parent
        @parent.as_action
      else
        @method_description.method
      end
    end

    def action_awareness
      if action_aware?
        if !@options.has_key?(:allow_nil)
          if @required
            @allow_nil = false
          else
            @allow_nil = true
          end
        end
        if as_action != "create"
          @required = false
        end
      end
    end

    def concern_subst(string)
      return string if string.nil? or !from_concern?

      original = string
      string = ":#{original}" if original.is_a? Symbol

      replaced = method_description.resource.controller._apipie_perform_concern_subst(string)

      return original if replaced == string
      return replaced.to_sym if original.is_a? Symbol
      return replaced
    end

    def preformat_text(text)
      concern_subst(Apipie.markup_to_html(text || ''))
    end

  end

end
