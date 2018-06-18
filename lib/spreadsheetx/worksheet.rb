module SpreadsheetX
  # Workbooks are made up of N Worksheets, this class represents a specific Worksheet.
  class Worksheet
    require 'date'

    attr_reader :sheet_id
    attr_reader :r_id
    attr_reader :name
    attr_reader :sheet_number

    # return a Worksheet object which relates to a specific Worksheet
    def initialize(archive, sheet_id, r_id, name)
      @sheet_id = sheet_id
      @name = name
      @target_file = sheet_target(archive, r_id)
      @sheet_number = @target_file.split('.')[0][-1]

      archive.each do |file|
        case file.name
          # open the workbook
        when "xl/#{@target_file}"
          # read contents of this file
          file_contents = file.get_input_stream.read

          # parse the XML and hold the doc
          @xml_doc = XML::Document.string(file_contents)
          # set the default namespace
          prefix = 'spreadsheetml'
          unless @xml_doc.root.namespaces.find_by_prefix(prefix)
            @xml_doc.root.namespaces.default_prefix = prefix
          end
        end
      end
    end

    def sheet_target(archive, r_id)
      target_file = ''

      archive.each do |file|
        case file.name
        when 'xl/_rels/workbook.xml.rels'
          doc = XML::Document.string file.get_input_stream.read
          name_space = doc.root.namespaces.default.href

          doc.find('//r:Relationship', "r:#{name_space}").each do |r|
            if r[:Id] == "rId#{r_id}"
              target_file = r[:Target]
              break
            end
          end
        end
      end
      target_file
    end

    def cell(col_number, row_number)
      cell_id = SpreadsheetX::Worksheet.cell_id(col_number, row_number)
      cell = find_cell(cell_id, row_number)
      raise "Cannot find cell by col number #{col_number} and row number #{row_number}" unless cell
      cell.content
    end

    # update the value of a particular cell, if the row or cell doesnt exist in the XML, then it will be created
    def update_cell(col_number, row_number, val, format = nil)
      cell_id = SpreadsheetX::Worksheet.cell_id(col_number, row_number)

      val_is_a_date = (val.is_a?(Date) || val.is_a?(Time) || val.is_a?(DateTime))

      # if the val is nil or an empty string, then just delete the cell
      if val.nil?
        if cell = find_cell(cell_id, row_number)
          cell.remove!
        end
        return
      end

      row = get_row(row_number)

      cell = row.find_first("spreadsheetml:c[@r='#{cell_id}']")
      # was this row found
      unless cell
        # build a new cell
        cell = XML::Node.new('c')
        cell['r'] = cell_id
        # add it to the other cells in this row
        row << cell
      end

      # are we setting a format
      cell['s'] = format.to_s if format

      # reset this attribute
      cell['t'] = ''

      # create the node which represents the value in the cell

      # numeric types
      if val.is_a?(Integer) || val.is_a?(Float)
        cell['t'] = 'n'

        cell_value = XML::Node.new('v')
        cell_value.content = val.to_s

        # if we are using a format, then dates are stored as floats, otherwise they get caught by string use a string
      elsif format && val_is_a_date

        cell_value = XML::Node.new('v')
        # dates are stored as flaots, otherwise use a string
        cell_value.content = (val.to_time.to_f / (60 * 60 * 24)).to_s

      else # assume its a string

        # put the strings inline to make life easier
        cell['t'] = 'inlineStr'

        # the string node looks like <is><t>string</t></is>
        is = XML::Node.new('is')
        t = XML::Node.new('t')
        t.content = val_is_a_date ? val.to_time.strftime('%Y-%m-%d %H:%M:%S') : val.to_s

        cell_value = (is << t)

      end

      # first clear out any existing values (nodes)
      cell.find('*').each(&:remove!)

      # now we put the value in the cell
      cell << cell_value
    end

    # the number of rows containing data this sheet has
    # NOTE: this is the count of those rows, not the length of the document
    def row_count
      count = 0
      # target the sheetData rows
      @xml_doc.find('spreadsheetml:sheetData/spreadsheetml:row').count
    end

    # returns the xml representation of this worksheet
    def to_s
      @xml_doc.to_s(indent: false).gsub(/\n/, "\r\n")
    end

    # turns a cell address into its excel name, 1,1 = A1  2,3 = C2 etc.
    def self.cell_id(col_number, row_number)
      raise 'There is no row 0 in an excel sheet, start at 1 instead' if row_number < 1
      raise 'There is no column 0 in an excel sheet, start at 1 instead' if col_number < 1
      letter = 'A'
      # some day, speed this up
      (col_number.to_i - 1).times { letter = letter.succ }
      "#{letter}#{row_number}"
    end

    def get_row(row_number)
      row = @xml_doc.find_first("spreadsheetml:sheetData/spreadsheetml:row[@r=#{row_number}]")
      # was this row found
      unless row
        # build a new row
        row = XML::Node.new('row')
        row['r'] = row_number.to_s

        # if there are no rows higher than this one, then add this row to the end of the sheetData
        next_largest = @xml_doc.find_first("spreadsheetml:sheetData/spreadsheetml:row[@r>#{row_number}]")
        if next_largest
          next_largest.prev = row
        else # there are no rows higher than this one
          # add this row to the end of the sheetData
          @xml_doc.find_first('spreadsheetml:sheetData') << row
        end
      end

      row
    end

    private

    def find_cell(cell_id, row_number)
      @xml_doc.find_first("spreadsheetml:sheetData/spreadsheetml:row[@r=#{row_number}]/spreadsheetml:c[@r='#{cell_id}']")
    end
  end
end
