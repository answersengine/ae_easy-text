require 'cgi'
require 'json'
require 'digest/sha1'
require 'ae_easy/core'
require 'ae_easy/text/version'

module AeEasy
  module Text
    # Create a hash from object
    #
    # @param [String,Hash,Object] object Object to create hash from.
    #
    # @return [String]
    def self.hash object
      object = object.hash if object.is_a? Hash
      Digest::SHA1.hexdigest object.to_s
    end

    # Encode text for valid HTML entities.
    #
    # @param [String] text Text to encode.
    #
    # @return [String]
    def self.encode_html text
      CGI.escapeHTML text
    end

    # Decode HTML entities from text .
    #
    # @param [String] text Text to decode.
    #
    # @return [String]
    def self.decode_html text
      CGI.unescapeHTML text
    end

    # Strip a value by trimming spaces, reducing secuential spaces into a
    #   single space, decode HTML entities and change encoding to UTF-8.
    #
    # @param [String,Object,nil] raw_text Text to strip.
    # @param [String] orig_encoding Text original encoding.
    #
    # @return [String,nil] `nil` when +raw_text+ is nil, else `String`.
    def self.strip raw_text, orig_encoding = 'ASCII'
      return nil if raw_text.nil?
      raw_text = raw_text.to_s unless raw_text.is_a? String
      regex = /(\s|\u3000|\u00a0)+/
      good_encoding = (raw_text =~ /\u3000/ || true) rescue false
      unless good_encoding
        raw_text = raw_text.force_encoding(orig_encoding).encode('UTF-8', invalid: :replace, undef: :replace)
        regex = /(\s|\u3000|\u00a0|\u00c2\u00a0)+/
      end
      text = raw_text.gsub(regex, ' ').strip
      text.nil? ? nil : decode_html(text)
    end

    # Default cell content parser used to parse cell element.
    #
    # @param [Nokogiri::Element] cell_element Cell element to parse.
    # @param [Hash] data Data hash to save parsed data into.
    # @param [String,Symbol] key Header column key being parsed.
    def self.default_parser cell_element, data, key
      return if cell_element.nil?
      cell_element.search('//i').remove if cell_element.search('//i').count > 0
      data[key] = strip cell_element.text
    end

    # Parse row data matching a selector using a header map to translate
    #   between columns and friendly keys.
    #
    # @param [Hash] opts ({}) Configuration options.
    # @option opts [Nokogiri::Element] :html Container element to search into.
    # @option opts [String] :selector CSS selector to match content cells.
    # @option opts [Boolean] :first_row_header (false) If true then first
    #   matching element will be assumed to be header and ignored.
    # @option opts [Hash{Symbol,String => Integer}] :header_map Header key vs
    #   index dictionary.
    # @option opts [Hash{Symbol,String => lambda,proc}] :column_parsers ({})
    #   Custom column parsers for advance data extraction.
    # @option opts [Boolean] :ignore_text_nodes (true) Ignore text nodes when
    #   retriving content cells and rows.
    #
    # @yieldparam [Hash{Symbol,String => Object}] data Parsed row data.
    # @yieldparam [Array] row Raw row data.
    # @yieldparam [Hash{Symbol,String => Integer}] header_map Header map used.
    # @yieldreturn [Boolean] `true` when valid, else `false`.
    #
    # @return [Array<Hash>,nil] Parsed rows data.
    def self.parse_content opts, &filter
      opts = {
        html: nil,
        selector: nil,
        first_row_header: false,
        header_map: {},
        column_parsers: {},
        ignore_text_nodes: true
      }.merge opts

      # Setup config
      data = []
      row_data = child_element = nil
      first = first_row_header = opts[:first_row_header]
      header_map = opts[:header_map]
      column_parsers = opts[:column_parsers]
      ignore_text_nodes = opts[:ignore_text_nodes]

      # Get and parse rows
      html_rows = opts[:html].css(opts[:selector])
      html_rows.each do |row|
        next if ignore_text_nodes && row.name == 'text'

        # First row header validation
        if first && first_row_header
          first = false
          next
        end

        # Extract content data
        row_data = {}
        header_map.each do |key, index|
          # Parse column html with default or custom parser
          children = row.children
          children = children.select{|i|i.name != 'text'} if ignore_text_nodes
          child_element = children[index]
          column_parsers[key].nil? ?
            default_parser(child_element, row_data, key) :
            column_parsers[key].call(child_element, row_data, key)
        end
        next unless filter.nil? || filter.call(row_data, row, header_map)
        data << row_data
      end
      data
    end

    # Extract column label and translate it into a frienly key.
    #
    # @param [Nokogiri::Element] element Html element to parse.
    # @param [Hash{Symbol,String => Regex,String}] label_map Label dictionary
    #   for translation into key.
    #
    # @return [Symbol,String] Translated key.
    def self.translate_label_to_key element, label_map
      return nil if element.nil?
      element.search('//i').remove if element.search('//i').count > 0
      text = strip element.text
      key_pair = label_map.find do |k,v|
        v.is_a?(Regexp) ? (text =~ v) : (text == v)
      end
      key = key_pair.nil? ? nil : key_pair[0]
    end

    # Parse header from selector and create a header map to match a column key
    #   with column index.
    #
    # @param [Hash] opts ({}) Configuration options.
    # @option opts [Nokogiri::Element] :html Container element to search into.
    # @option opts [String] :selector CSS selector to match header cells.
    # @option opts [Hash{Symbol,String => Regex,String}] :column_key_label_map
    #   Key vs. label dictionary.
    # @option opts [Boolean] :first_row_header (false) If true then selector
    #   first matching row will be used as header for parsing.
    # @option opts [Boolean] :ignore_text_nodes (true) Ignore text nodes when
    #   retriving header cells and rows.
    #
    # @return [Hash{Symbol,String => Integer},nil] Key vs. column index map.
    def self.parse_header_map opts = {}
      opts = {
        html: nil,
        selector: nil,
        column_key_label_map: {},
        first_row_header: false,
        ignore_text_nodes: true
      }.merge opts

      # Setup config
      dictionary = opts[:column_key_label_map]
      ignore_text_nodes = opts[:ignore_text_nodes]
      data = []
      column_map = nil

      # Extract and parse header rows
      html_rows = opts[:html].css(opts[:selector]) rescue nil
      return nil if html_rows.nil?
      html_rows = [html_rows.first] if opts[:first_row_header]
      html_rows.each do |row|
        next if ignore_text_nodes && row.name == 'text'

        column_map = {}
        children = row.children
        children = children.select{|i|i.name != 'text'} if ignore_text_nodes
        children.each_with_index do |col, index|
          # Parse and map column header
          column_key = translate_label_to_key col, dictionary
          next if column_key.nil?
          column_map[column_key] = index
        end
        data << column_map
      end
      data&.first
    end

    # Parse data from a horizontal table like structure matching a selectors and
    #   using a header map to match columns.
    #
    # @param [Hash] opts ({}) Configuration options.
    # @option opts [Nokogiri::Element] :html Container element to search into.
    # @option opts [String] :header_selector Header column elements selector.
    # @option opts [Hash{Symbol,String => Regex,String}] :header_key_label_map
    #   Header key vs. label dictionary to match column indexes.
    # @option opts [String] :content_selector Content row elements selector.
    # @option opts [Boolean] :first_row_header (false) If true then selector
    #   first matching row will be used as header for parsing.
    # @option opts [Hash{Symbol,String => lambda,proc}] :column_parsers ({})
    #   Custom column parsers for advance data extraction.
    # @option opts [Boolean] :ignore_text_nodes (true) Ignore text nodes when
    #   retriving cells and rows.
    #
    # @yieldparam [Hash{Symbol,String => Object}] data Parsed content row data.
    # @yieldparam [Array] row Raw content row data.
    # @yieldparam [Hash{Symbol,String => Integer}] header_map Header map used.
    # @yieldreturn [Boolean] `true` when valid, else `false`.
    #
    # @return [Hash{Symbol => Array,Hash,nil}] Hash data is as follows:
    #   * `[Hash] :header_map` Header map used.
    #   * `[Array<Hash>,nil] :data` Parsed rows data.
    def self.parse_table opts = {}, &filter
      opts = {
        html: nil,
        header_selector: nil,
        header_key_label_map: {},
        content_selector: nil,
        first_row_header: false,
        column_parsers: {},
        ignore_text_nodes: true
      }.merge opts
      return nil if opts[:html].nil?
      header_map = self.parse_header_map html: opts[:html],
        selector: opts[:header_selector],
        column_key_label_map: opts[:header_key_label_map],
        first_row_header: opts[:first_row_header],
        ignore_text_nodes: opts[:ignore_text_nodes]
      return nil if header_map.nil?
      data = self.parse_content html: opts[:html],
        selector: opts[:content_selector],
        header_map: header_map,
        first_row_header: opts[:first_row_header],
        column_parsers: opts[:column_parsers],
        ignore_text_nodes: opts[:ignore_text_nodes],
        &filter
      {header_map: header_map, data: data}
    end

    # Parse data from a vertical table like structure matching a selectors and
    #   using a header map to match columns.
    #
    # @param [Hash] opts ({}) Configuration options.
    # @option opts [Nokogiri::Element] :html Container element to search into.
    # @option opts [String] :row_selector Vertical row like elements selector.
    # @option opts [String] :header_selector Header column elements selector.
    # @option opts [Hash{Symbol,String => Regex,String}] :header_key_label_map
    #   Header key vs. label dictionary to match column indexes.
    # @option opts [String] :content_selector Content row elements selector.
    # @option opts [Hash{Symbol,String => lambda,proc}] :column_parsers ({})
    #   Custom column parsers for advance data extraction.
    # @option opts [Boolean] :ignore_text_nodes (true) Ignore text nodes when
    #   retriving cells and rows.
    #
    # @yieldparam [Hash{Symbol,String => Object}] data Parsed content row data.
    # @yieldparam [Array] row Raw content row data.
    # @yieldparam [Hash{Symbol,String => Integer}] header_map Header map used.
    # @yieldreturn [Boolean] `true` when valid, else `false`.
    #
    # @return [Hash{Symbol => Array,Hash,nil}] Hash data is as follows:
    #   * `[Hash] :header_map` Header map used.
    #   * `[Array<Hash>,nil] :data` Parsed rows data.
    def self.parse_vertical_table opts = {}, &filter
      opts = {
        html: nil,
        row_selector: nil,
        header_selector: nil,
        header_key_label_map: {},
        content_selector: nil,
        column_parsers: {},
        ignore_text_nodes: true
      }.merge opts
      return nil if opts[:html].nil?

      # Setup config
      data = {}
      dictionary = opts[:header_key_label_map]
      column_parsers = opts[:column_parsers]

      # Extract headers and content
      html_rows = opts[:html].css(opts[:row_selector]) rescue nil
      return nil if html_rows.nil?
      html_rows.each do |row|
        # Parse and map column header
        header_element = row.css(opts[:header_selector])
        key = translate_label_to_key header_element, dictionary
        next if key.nil? || key == ''

        # Parse column html with default or custom parser
        content_element = row.css(opts[:content_selector])
        column_parsers[key].nil? ?
          default_parser(content_element, data, key) :
          column_parsers[key].call(content_element, data, key)
      end
      data
    end
  end
end
