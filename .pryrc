# frozen_string_literal: true

Pry.config.print = proc do |output, value, _pry_|
  case value
  when ActiveRecord::Relation
    output.puts "=> #{value}"
  else
    Pry::ColorPrinter.default(output, value, _pry_)
  end
end
