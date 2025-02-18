# frozen_string_literal: true

require "good_job/cli"

namespace :good_job do
  desc "Start Good Job process"
  task start: :environment do
    GoodJob::CLI.start(["start"])
  end
end
