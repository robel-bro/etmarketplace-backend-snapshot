# config/schedule.rb

# ── Promotional notifications ─────────────────────────────
every :monday, at: '10:00 am' do
  rake "notifications:send_promotions"
end

every :wednesday, at: '10:00 am' do
  rake "notifications:send_promotions"
end

every :friday, at: '10:00 am' do
  rake "notifications:send_promotions"
end

# ── Membership expiry – runs daily at midnight ────────────
every 1.day, at: '12:00 am' do
  runner "MembershipExpiryJob.perform_later"
end

# ── Expired hold cleanup ─────────────────────────────────
# This job releases expired cart items (15‑minute holds)
# AND orphaned expired reservations.
# Run every 2 minutes for real‑time fairness.
every 2.minutes do
  runner "ReleaseExpiredReservationsJob.perform_now"
end

# ── Auto‑cancel unpaid online orders ─────────────────────
# If an online payment (Telebirr/Chapa) is not completed
# within 30 minutes, cancel the order and release stock.
every 5.minutes do
  runner "AutoCancelUnpaidOrdersJob.perform_now"
end

# ── SMART LISTING: update trending scores every hour ──────
every 1.hour do
  runner "Product.update_trending_scores!; Package.update_trending_scores!"
end