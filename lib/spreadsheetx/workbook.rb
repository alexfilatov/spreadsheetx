module SpreadsheetX
  # This class represents an XLSX Document on disk
  class Workbook
    attr_reader :path
    attr_reader :worksheets
    attr_reader :formats

    # return a Workbook object which relates to an existing xlsx file on disk
    def initialize(path)
      @path = path
      Zip::File.open(path) do |archive|
        archive.each do |file|
          case file.name

            # open the workbook
          when 'xl/workbook.xml'

            # read contents of this file
            file_contents = file.get_input_stream.read

            # parse the XML and build the worksheets
            @worksheets = []
            # parse the XML and hold the doc
            xml_doc = XML::Document.string(file_contents)
            # set the default namespace
            xml_doc.root.namespaces.default_prefix = 'spreadsheetml'

            xml_doc.find('spreadsheetml:sheets/spreadsheetml:sheet').each do |node|
              sheet_id = node['sheetId'].to_i
              r_id = node['id'].gsub('rId', '').to_i
              name = node['name'].to_s
              @worksheets.push SpreadsheetX::Worksheet.new(archive, sheet_id, r_id, name)
            end

            # open the styles, to get the cell formats
          when 'xl/styles.xml'

            # read contents of this file
            file_contents = file.get_input_stream.read

            # parse the XML and build the worksheets
            @formats = []
            # parse the XML and hold the doc
            xml_doc = XML::Document.string(file_contents)
            # set the default namespace
            xml_doc.root.namespaces.default_prefix = 'spreadsheetml'

            format_id = 0
            xml_doc.find('spreadsheetml:numFmts/spreadsheetml:numFmt').each do |node|
              @formats.push SpreadsheetX::CellFormat.new((format_id += 1), node['formatCode'])
            end

          end
        end
      end
    end

    # saves the binary form of the complete xlsx file to a new xlsx file
    def save(destination_path)
      # overwrite files
      Zip.continue_on_exists_proc = true

      # copy the xlsx file to the destination
      FileUtils.cp(@path, destination_path)

      # replace the xlsx files with the new workbooks
      Zip::File.open(destination_path) do |ar|
        # replace with the new worksheets
        @worksheets.each do |worksheet|
          file = file_name = "sheet#{worksheet.sheet_number}.xml"
          Tempfile.open do |file|
            file.write worksheet.to_s
            ar.add("xl/worksheets/#{file_name}", file)
          end
        end
      end
    end
  end
end
