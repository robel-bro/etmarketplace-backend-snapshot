namespace :dynamic_deals do
  desc "Recalculate flash sale and super deal flags"
  task recompute: :environment do
    DynamicDealAssignmentJob.perform_now
  end
end