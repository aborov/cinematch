#!/usr/bin/env ruby
require_relative 'lib/memory_monitor'

puts "Memory Management Test"
puts "======================"

# Initialize memory monitor
memory_monitor = MemoryMonitor.new
puts "Initial memory usage: #{memory_monitor.mb.round(2)} MB"

# Test memory threshold checks
threshold = 400
puts "Memory threshold: #{threshold} MB"
puts "Exceeds threshold? #{memory_monitor.exceeds_threshold?(threshold)}"
puts "Below 70% of threshold? #{memory_monitor.below_threshold?(threshold)}"

# Test memory trend tracking
memory_readings = []
5.times do |i|
  # Allocate some memory to simulate usage
  array = Array.new(1000000 * (i + 1)) { |j| j }
  memory_readings << memory_monitor.mb
  puts "Memory reading #{i+1}: #{memory_readings.last.round(2)} MB"
  array = nil # Release the memory
end

# Check if memory is trending up
memory_trend_increasing = memory_readings.size >= 3 && memory_readings[-1] > memory_readings[-3]
puts "Memory trending up? #{memory_trend_increasing}"

# Test garbage collection
puts "Memory before GC: #{memory_monitor.mb.round(2)} MB"
GC.start(full_mark: true, immediate_sweep: true)
puts "Memory after GC: #{memory_monitor.mb.round(2)} MB"

# Test batch size adjustment
batch_size = 30
max_batch_size = 300
min_batch_size = 5
current_memory = memory_monitor.mb

puts "\nBatch Size Adjustment Test"
puts "=========================="
puts "Initial batch size: #{batch_size}"
puts "Max batch size: #{max_batch_size}"
puts "Min batch size: #{min_batch_size}"
puts "Current memory: #{current_memory.round(2)} MB"

# Simulate different memory scenarios
memory_scenarios = [
  { level: "Critical", memory: threshold * 1.2, factor: 0.5 },
  { level: "High", memory: threshold * 1.1, factor: 0.7 },
  { level: "Warning", memory: threshold * 0.9, factor: 0.8 },
  { level: "Low", memory: threshold * 0.6, factor: 1.25 }
]

memory_scenarios.each do |scenario|
  puts "\nScenario: #{scenario[:level]} memory usage (#{scenario[:memory].round(2)} MB)"
  
  if scenario[:level] == "Low"
    new_batch_size = [(batch_size * scenario[:factor]).to_i, max_batch_size].min
    puts "Increasing batch size from #{batch_size} to #{new_batch_size}"
  else
    new_batch_size = [(batch_size * scenario[:factor]).to_i, min_batch_size].max
    puts "Reducing batch size from #{batch_size} to #{new_batch_size}"
  end
  
  batch_size = new_batch_size
end

puts "\nTest completed successfully!" 
