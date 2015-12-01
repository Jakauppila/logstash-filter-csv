# encoding: utf-8
require "logstash/filters/base"
require "logstash/namespace"

require "csv"

# The CSV filter takes an event field containing CSV data, parses it,
# and stores it as individual fields (can optionally specify the names).
# This filter can also parse data with any separator, not just commas.
class LogStash::Filters::CSV < LogStash::Filters::Base
  config_name "csv"

  # The CSV data in the value of the `source` field will be expanded into a
  # data structure.
  config :source, :validate => :string, :default => "message"

  # Define a list of column names (in the order they appear in the CSV,
  # as if it were a header line). If `columns` is not configured, or there
  # are not enough columns specified, the default column names are
  # "column1", "column2", etc. In the case that there are more columns
  # in the data than specified in this column list, extra columns will be auto-numbered:
  # (e.g. "user_defined_1", "user_defined_2", "column3", "column4", etc.)
  config :columns, :validate => :array, :default => []

  # Define the column separator value. If this is not specified, the default
  # is a comma `,`.
  # Optional.
  config :separator, :validate => :string, :default => ","

  # Define the character used to quote CSV fields. If this is not specified
  # the default is a double quote `"`.
  # Optional.
  config :quote_char, :validate => :string, :default => '"'

  # Define target field for placing the data.
  # Defaults to writing to the root of the event.
  config :target, :validate => :string

  # Define whether column names should autogenerated or not.
  # Defaults to true. If set to false, columns not having a header specified will not be parsed.
  config :autogenerate_column_names, :validate => :boolean, :default => true

  # Define whether empty columns should be skipped.
  # Defaults to false. If set to true, columns containing no value will not get set.
  config :skip_empty_columns, :validate => :boolean, :default => false

  # Define a set of datatype conversions to be applied to columns.
  # Possible conversions are integer, float, date, date_time, boolean
  #
  # # Example:
  # [source,ruby]
  #     filter {
  #       csv {
  #         convert => { "column1" => "integer", "column2" => "boolean" }
  #       }
  #     }
  config :convert, :validate => :hash, :default => {}


  ##
  # List of valid conversion types used for the convert option
  ##
  VALID_CONVERT_TYPES = [ "integer", "float", "date", "date_time", "boolean" ].freeze


  def register
    # validate conversion types to be the valid ones.
    @convert.each_pair do |column, type|
      if !VALID_CONVERT_TYPES.include?(type)
        raise LogStash::ConfigurationError, "#{type} is not a valid conversion type."
      end
    end
  end # def register

  def filter(event)
    @logger.debug("Running csv filter", :event => event)

    if event[@source]
      source = event[@source].clone
      begin
        values = CSV.parse_line(source, :col_sep => @separator, :quote_char => @quote_char)
        if @target.nil?
          # Default is to write to the root of the event.
          dest = event
        else
          dest = event[@target] ||= {}
        end

        values.each_index do |i|
          if !(@skip_empty_columns && (values[i].nil? || values[i].empty?))
            if !ignore_field?(i)
              field_name       = @columns[i] ? @columns[i] : "column#{i+1}"
              dest[field_name] = if should_transform?(field_name)
                                   transform(field_name, values[i])
                                 else
                                   values[i]
                                 end
            end
          end
        end
        filter_matched(event)
      rescue => e
        event.tag "_csvparsefailure"
        @logger.warn("Trouble parsing csv", :field => @source, :source => source, :exception => e)
        return
      end # begin
    end # if event

    @logger.debug("Event after csv filter", :event => event)

  end # def filter

  private

  def ignore_field?(index)
    !@columns[index] && !@autogenerate_column_names
  end

  def should_transform?(field_name)
    !@convert[field_name].nil?
  end

  def transform(field_name, value)
    transformation = @convert[field_name].to_sym
    converters[transformation].call(value)
  end

  def converters
    @converters ||= {
      :integer => lambda do |value|
        CSV::Converters[:integer].call(value)
      end,
      :float => lambda do |value|
        CSV::Converters[:float].call(value)

      end,
      :date => lambda do |value|
        CSV::Converters[:date].call(value)

      end,
      :date_time => lambda do |value|
        CSV::Converters[:date_time].call(value)
      end,
      :boolean => lambda do |value|
         value = value.strip.downcase
         return false if value == "false"
         return true  if value == "true"
         return value
      end
    }
  end
end # class LogStash::Filters::Csv

