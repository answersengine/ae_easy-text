require 'test_helper'

describe 'ae_easy-text' do
  describe 'unit test' do
    it 'should generate a consistent hash' do
      hash_a = AeEasy::Text.hash 'abc'
      hash_b = AeEasy::Text.hash 'abc'
      assert_kind_of String, hash_a
      refute_empty hash_a
      assert_equal hash_b, hash_a
    end

    it 'should generate a unique hash' do
      hash_a = AeEasy::Text.hash 'aaa'
      hash_b = AeEasy::Text.hash 'bbb'
      assert_kind_of String, hash_a
      refute_empty hash_a
      refute_equal hash_b, hash_a
    end

    it 'should generate a consistent hash when number' do
      hash_a = AeEasy::Text.hash 123
      hash_b = AeEasy::Text.hash 123
      assert_kind_of String, hash_a
      refute_empty hash_a
      assert_equal hash_b, hash_a
    end

    it 'should generate a unique hash when number' do
      hash_a = AeEasy::Text.hash 111
      hash_b = AeEasy::Text.hash 222
      assert_kind_of String, hash_a
      refute_empty hash_a
      refute_equal hash_b, hash_a
    end

    it 'should generate a consistent hash when hash' do
      hash_a = AeEasy::Text.hash({'aaa' => 111, 'bbb' => 'BBB'})
      hash_b = AeEasy::Text.hash({'bbb' => 'BBB', 'aaa' => 111})
      assert_kind_of String, hash_a
      refute_empty hash_a
      assert_equal hash_b, hash_a
    end

    it 'should generate a unique hash when hash' do
      hash_a = AeEasy::Text.hash({'aaa' => 'AAA'})
      hash_b = AeEasy::Text.hash({'aaa' => '111'})
      assert_kind_of String, hash_a
      refute_empty hash_a
      refute_equal hash_b, hash_a
    end

    it 'should encode html entities' do
      data = AeEasy::Text.encode_html 'abc&abc>'
      expected = 'abc&amp;abc&gt;'
      assert_equal expected, data
    end

    it 'should decode html entities' do
      data = AeEasy::Text.decode_html 'abc&amp;abc&gt;'
      expected = 'abc&abc>'
      assert_equal expected, data
    end

    describe 'should strip data' do
      it 'with spaces' do
        data = AeEasy::Text.strip '    abc     '
        expected = 'abc'
        assert_equal expected, data
      end

      it 'and return nil when nil' do
        assert_nil AeEasy::Text.strip(nil)
      end

      it 'and decode html entities' do
        data = AeEasy::Text.strip '    abc&amp;&gt;     '
        expected = 'abc&>'
        assert_equal expected, data
      end

      it 'with bad encoding' do
        data = AeEasy::Text.strip "\xaa abc".force_encoding('ASCII')
        expected = "\ufffd abc"
        assert_equal expected, data
      end
    end

    it 'should remove <i> elements with default parser' do
      html = '<span><i><b>  hello   </b><span>'
      element = Nokogiri::HTML.fragment html
      data = {}
      AeEasy::Text.default_parser element, data, :aaa
      expected = 'hello'
      assert_equal expected, data[:aaa]
    end

    it 'should do nothing with default parser when element is nil' do
      data = {}
      AeEasy::Text.default_parser nil, data, :aaa
      expected = {}
      assert_equal expected, data
    end

    it 'should parse contents from table' do
      html = '
        <table>
          <thead>
            <tr>
              <th>number   </th>
              <th>  my text<th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>111   </td>
              <td>aaa</td>
            </tr>
            <tr>
              <td>222</td>
              <td>   bbb</td>
            </tr>
          </tbody>
        </table>
      '
      header_map = {
        id: 0,
        name: 1
      }
      element = Nokogiri::HTML.fragment html
      data = AeEasy::Text.parse_content(
        html: element,
        selector: 'tbody tr',
        header_map: header_map
      )
      expected = [
        {id: '111', name: 'aaa'},
        {id: '222', name: 'bbb'}
      ]
      assert_equal expected, data
    end

    it 'should parse contents with custom column parser' do
      html = '
        <table>
          <thead>
            <tr>
              <th>number   </th>
              <th> complicated  stuff</th>
              <th>  my text</th>
              <th>some other stuff</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>111   </td>
              <td> aaa<span class="stuff">123ddd</span> bb</td>
              <td>aaa</td>
              <td>ccc</td>
            </tr>
            <tr>
              <td>222</td>
              <td>cc567<span class="stuff">890eee11</span></td>
              <td>   bbb</td>
              <td>ddd</td>
            </tr>
          </tbody>
        </table>
      '
      header_map = {
        id: 0,
        my_type: 1,
        name: 2
      }
      element = Nokogiri::HTML.fragment html
      my_type_parser = lambda do |element, data, key|
        text = AeEasy::Text.strip element.css('.stuff').text.gsub(/[0-9]/, '')
        numbers = AeEasy::Text.strip element.css('.stuff').text.gsub(/[^0-9]/, '')
        data[key] = text
        data[:numbers] = numbers
      end
      data = AeEasy::Text.parse_content(
        html: element,
        selector: 'tbody tr',
        header_map: header_map,
        column_parsers: {
          my_type: my_type_parser
        }
      )
      expected = [
        {id: '111', name: 'aaa', my_type: 'ddd', numbers: '123'},
        {id: '222', name: 'bbb', my_type: 'eee', numbers: '89011'}
      ]
      assert_equal expected, data
    end

    it 'should parse contents from table with headers on first row' do
      html = '
        <table>
          <tr>
            <td>number   </td>
            <td>  my text<td>
          </tr>
          <tr>
            <td>111   </td>
            <td>aaa</td>
          </tr>
          <tr>
            <td>222</td>
            <td>   bbb</td>
          </tr>
        </table>
      '
      header_map = {
        id: 0,
        name: 1
      }
      element = Nokogiri::HTML.fragment html
      data = AeEasy::Text.parse_content(
        first_row_header: true,
        html: element,
        selector: 'tr',
        header_map: header_map
      )
      expected = [
        {id: '111', name: 'aaa'},
        {id: '222', name: 'bbb'}
      ]
      assert_equal expected, data
    end

    it 'should translate label to key' do
      html = '<span><i><b>  hello   </b><span>'
      element = Nokogiri::HTML.fragment html
      label_map = {
        id: 'hello',
        name: 'bla'
      }
      data = AeEasy::Text.translate_label_to_key element, label_map
      expected = :id
      assert_equal expected, data
    end

    it 'should return nil when translated label not found' do
      html = '<span><i><b>  hello   </b><span>'
      element = Nokogiri::HTML.fragment html
      label_map = {
        id: 'aaa',
        name: 'bla'
      }
      data = AeEasy::Text.translate_label_to_key element, label_map
      assert_nil data
    end

    it 'should return nil when translated label with nil element' do
      label_map = {
        id: 'aaa',
        name: 'bla'
      }
      data = AeEasy::Text.translate_label_to_key nil, label_map
      assert_nil data
    end

    it 'should parse header from table' do
      html = '
        <table>
          <thead>
            <tr>
              <th>number   </th>
              <th>  my text<th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>111   </td>
              <td>aaa</td>
            </tr>
            <tr>
              <td>222</td>
              <td>   bbb</td>
            </tr>
          </tbody>
        </table>
      '
      label_map = {
        id: /number/,
        name: 'my text'
      }
      element = Nokogiri::HTML.fragment html
      data = AeEasy::Text.parse_header_map(
        html: element,
        selector: 'thead tr',
        column_key_label_map: label_map,
      )
      expected = {
        id: 0,
        name: 1
      }
      assert_equal expected, data
    end

    it 'should parse header from table with headers on first row' do
      html = '
        <table>
          <tr>
            <td>number   </td>
            <td>  my text<td>
          </tr>
          <tr>
            <td>111   </td>
            <td>aaa</td>
          </tr>
          <tr>
            <td>222</td>
            <td>   bbb</td>
          </tr>
        </table>
      '
      label_map = {
        id: 'number',
        name: /my\s+text/
      }
      element = Nokogiri::HTML.fragment html
      data = AeEasy::Text.parse_header_map(
        first_row_header: true,
        html: element,
        selector: 'tr',
        column_key_label_map: label_map
      )
      expected = {
        id: 0,
        name: 1
      }
      assert_equal expected, data
    end

    it 'should parse a vertical table' do
      html = '
        <table>
          <tr>
            <td>number   </td>
            <td> 333 </td>
          </tr>
          <tr>
            <td> product <i class="something"> name</td>
            <td>cc c</td>
          </tr>
        </table>
      '
      label_map = {
        id: /number/,
        'name' => 'product name'
      }
      element = Nokogiri::HTML.fragment html
      data = AeEasy::Text.parse_vertical_table(
        html: element,
        row_selector: 'tr',
        header_selector: 'td:first',
        content_selector: 'td:last',
        header_key_label_map: label_map,
      )
      expected = {id: '333', 'name' => 'cc c'}
      assert_equal expected, data
    end
  end

  describe 'integration test' do
    it 'should parse a table' do
      html = '
        <table>
          <thead>
            <tr>
              <th>number  abc   </th>
              <th> not important stuff </th>
              <th>  my text<th>
              <th> some other ignored stuff</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>333   </td>
              <td>111</td>
              <td>cc c</td>
              <td>aaa</td>
            </tr>
            <tr>
              <td>444</td>
              <td>bbb</td>
              <td>   ddd</td>
              <td>222</td>
            </tr>
          </tbody>
        </table>
      '
      label_map = {
        id_number: /number\s+abc/,
        'name' => 'my text'
      }
      element = Nokogiri::HTML.fragment html
      data = AeEasy::Text.parse_table(
        html: element,
        header_selector: 'thead tr',
        content_selector: 'tbody tr',
        header_key_label_map: label_map,
      )
      expected = {
        header_map: {
          id_number: 0,
          'name' => 2
        },
        data: [
          {id_number: '333', 'name' => 'cc c'},
          {id_number: '444', 'name' => 'ddd'}
        ]
      }
      assert_equal expected, data
    end

    it 'should parse a table with headers on first row' do
      html = '
        <table>
          <tr>
            <td>number  <i class="icon">   abc </td>
            <td>  my text<td>
          </tr>
          <tr>
            <td>777   </td>
            <td>ggg</td>
          </tr>
          <tr>
            <td>888</td>
            <td>   hhh</td>
          </tr>
        </table>
      '
      label_map = {
        'id' => 'number abc',
        product_name: /my\s+text/
      }
      element = Nokogiri::HTML.fragment html
      data = AeEasy::Text.parse_table(
        first_row_header: true,
        html: element,
        header_selector: 'tr',
        content_selector: 'tr',
        header_key_label_map: label_map,
      )
      expected = {
        header_map: {
          'id' => 0,
          product_name: 1
        },
        data: [
          {'id' => '777', product_name: 'ggg'},
          {'id' => '888', product_name: 'hhh'}
        ]
      }
      assert_equal expected, data
    end

    it 'should parse contents with custom column parser' do
      html = '
        <table>
          <thead>
            <tr>
              <th>number   </th>
              <th> complicated  stuff</th>
              <th>  my text</th>
              <th>some other stuff</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>111   </td>
              <td> aaa<span class="stuff">777fff</span> bb</td>
              <td>aaa</td>
              <td>ccc</td>
            </tr>
            <tr>
              <td>222</td>
              <td>cc567<span class="stuff">88g8gg11</span></td>
              <td>   bbb</td>
              <td>ddd</td>
            </tr>
          </tbody>
        </table>
      '
      label_map = {
        id: 'number',
        my_type: 'complicated stuff',
        name: /my\s+text/
      }
      element = Nokogiri::HTML.fragment html
      my_type_parser = lambda do |element, data, key|
        text = AeEasy::Text.strip element.css('.stuff').text.gsub(/[0-9]/, '')
        numbers = AeEasy::Text.strip element.css('.stuff').text.gsub(/[^0-9]/, '')
        data[key] = text
        data[:numbers] = numbers
      end
      data = AeEasy::Text.parse_table(
        html: element,
        header_selector: 'thead tr',
        content_selector: 'tbody tr',
        header_key_label_map: label_map,
        column_parsers: {
          my_type: my_type_parser
        }
      )
      expected = {
        header_map: {
          id: 0,
          my_type: 1,
          name: 2
        },
        data: [
          {id: '111', name: 'aaa', my_type: 'fff', numbers: '777'},
          {id: '222', name: 'bbb', my_type: 'ggg', numbers: '88811'}
        ]
      }
      assert_equal expected, data
    end
  end
end
