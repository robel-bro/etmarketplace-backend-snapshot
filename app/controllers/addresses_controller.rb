# app/controllers/addresses_controller.rb

class AddressesController < ApplicationController
  before_action :require_authentication
  before_action :set_address, only: [:show, :update, :destroy]

  def index
    @addresses = current_user.addresses
    render json: @addresses.as_json(
      include: [:region, :zone, :woreda],
      methods: :full_address
    )
  end

  def show
    render json: @address.as_json(
      include: [:region, :zone, :woreda],
      methods: :full_address
    )
  end

  def create
    @address = current_user.addresses.build(address_params)
    @address.phone = current_user.phone if @address.phone.blank?

    # If the user sent coordinates directly (manual pin) and didn't specify source,
    # treat it as a manual correction.
    if @address.latitude.present? && @address.longitude.present? && @address.source.blank?
      @address.source = 'manual'
    end

    if @address.save
      # Update the address cache when a manual correction is saved,
      # so future identical address text returns the verified pin instantly.
      update_address_cache(@address) if @address.source == 'manual'

      render json: @address.as_json(
        include: [:region, :zone, :woreda],
        methods: :full_address
      ), status: :created
    else
      render json: { errors: @address.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @address.update(address_params)
      update_address_cache(@address) if @address.source == 'manual'
      render json: @address.as_json(
        include: [:region, :zone, :woreda],
        methods: :full_address
      )
    else
      render json: { errors: @address.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @address.destroy
    head :no_content
  end

  private

  def set_address
    @address = current_user.addresses.find(params[:id])
  end

  # ★ FIXED: Accept both nested (params[:address]) and flat params.
  def address_params
    if params[:address].present?
      params.require(:address).permit(
        :region_id, :zone_id, :woreda_id,
        :address_line, :landmark, :is_default,
        :sub_city, :building_name, :latitude, :longitude,
        :phone, :delivery_notes,
        :city, :woreda_text, :street, :source
      )
    else
      params.permit(
        :region_id, :zone_id, :woreda_id,
        :address_line, :landmark, :is_default,
        :sub_city, :building_name, :latitude, :longitude,
        :phone, :delivery_notes,
        :city, :woreda_text, :street, :source
      )
    end
  end

  def coordinates_present?
    # This method is no longer used, but kept for backward compatibility.
    params[:latitude].present? && params[:longitude].present?
  end

  # ─── Self‑learning address cache ──────────────────
  # When a user manually corrects a pin, we store the corrected
  # coordinates and structured fields in the address_cache table.
  # Future uses of the same raw text bypass geocoding entirely.
  def update_address_cache(address)
    return if address.address_line.blank? || address.latitude.blank? || address.longitude.blank?

    cache = AddressCache.find_or_initialize_by(raw_address: address.address_line.strip.downcase)
    cache.assign_attributes(
      latitude:          address.latitude,
      longitude:         address.longitude,
      formatted_address: address.full_address,
      city:              address.city,
      subcity:           address.sub_city,
      woreda:            address.woreda_text,
      street:            address.street,
      landmark:          address.landmark,
      source:            'manual',
      corrected:         true
    )
    cache.save!
  rescue => e
    Rails.logger.warn "AddressCache update failed: #{e.message}"
  end
end