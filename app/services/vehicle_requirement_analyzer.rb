# app/services/vehicle_requirement_analyzer.rb
class VehicleRequirementAnalyzer
  # Admin-configurable thresholds – loaded from Setting
  DEFAULTS = {
    'volumetric_factor' => 5000,                # cm³ per kg
    'vehicle_weight_thresholds' => {
      'motorcycle' => 20.0,
      'car'        => 200.0,
      'van'        => 1000.0,
      'truck'      => Float::INFINITY
    },
    'vehicle_volume_thresholds' => {
      'motorcycle' => 80_000.0,     # 80 liters
      'car'        => 500_000.0,    # 500 liters
      'van'        => 2_000_000.0,  # 2 m³
      'truck'      => Float::INFINITY
    },
    'vehicle_refrigerated_capable' => ['van', 'truck'],
    'vehicle_fragile_capable' => ['car', 'van', 'truck'],
    'base_weight_kg' => 5.0,
    'base_volume_cm3' => 10_000.0,
    'stop_fee' => 15.0,
    'express_surcharge_percent' => 20.0,
    'fragile_surcharge' => 50.0,
    'refrigerated_surcharge' => 100.0
  }.freeze

  attr_reader :required_type, :actual_weight, :volume, :volumetric_weight,
              :chargeable_weight, :refrigerated_needed, :fragile_needed,
              :total_pickup_points

  def initialize(order)
    @order = order
    @line_items = order.line_items.includes(:product, package: { package_products: :product }).to_a
    @actual_weight = 0.0
    @volume = 0.0
    @volumetric_weight = 0.0
    @chargeable_weight = 0.0
    @refrigerated_needed = false
    @fragile_needed = false
    @total_pickup_points = 1  # at least one (seller)
    analyze
  end

  def self.determine_vehicle_type(line_items)
    new(Struct.new(:line_items).new(line_items)).required_type
  end

  private

  def analyze
    @line_items.each do |li|
      if li.product.present?
        process_product_line_item(li)
      elsif li.package.present?
        process_package_line_item(li)
      end
    end

    # Calculate volumetric weight based on total volume and admin factor
    factor = settings['volumetric_factor'].to_f
    @volumetric_weight = factor > 0 ? (@volume / factor).round(2) : 0.0
    @chargeable_weight = [@actual_weight, @volumetric_weight].max.round(2)

    # Determine required vehicle type using thresholds
    @required_type = select_vehicle_type
  end

  def process_product_line_item(li)
    product = li.product
    variant = find_variant_for_product(li)

    weight = variant&.weight_kg || product.weight_kg || 1.0
    length = variant&.length_cm || product.length_cm || 0
    width  = variant&.width_cm  || product.width_cm  || 0
    height = variant&.height_cm || product.height_cm || 0

    @actual_weight += weight.to_f * li.quantity
    @volume += (length.to_f * width.to_f * height.to_f) * li.quantity

    # Special requirements: variant overrides product
    attrs = product.product_attributes || {}
    refrigerated = variant&.refrigerated.nil? ? attrs['refrigerated'].to_s.downcase == 'true' : variant.refrigerated?
    fragile = variant&.fragile.nil? ? attrs['fragile'].to_s.downcase == 'true' : variant.fragile?
    @refrigerated_needed ||= refrigerated
    @fragile_needed ||= fragile
  end

  def process_package_line_item(li)
    package = li.package
    # For packages, each component's weight and volume is summed
    package.package_products.each do |pp|
      product = pp.product
      next unless product

      variant_attrs = pp.variant_attributes.presence || li.variant_attributes.presence
      variant = product.find_variant(variant_attrs) rescue nil

      weight = variant&.weight_kg || product.weight_kg || 1.0
      length = variant&.length_cm || product.length_cm || 0
      width  = variant&.width_cm  || product.width_cm  || 0
      height = variant&.height_cm || product.height_cm || 0

      component_qty = li.quantity  # whole package quantity

      @actual_weight += weight.to_f * component_qty
      @volume += (length.to_f * width.to_f * height.to_f) * component_qty

      attrs = product.product_attributes || {}
      refrigerated = variant&.refrigerated.nil? ? attrs['refrigerated'].to_s.downcase == 'true' : variant.refrigerated?
      fragile = variant&.fragile.nil? ? attrs['fragile'].to_s.downcase == 'true' : variant.fragile?
      @refrigerated_needed ||= refrigerated
      @fragile_needed ||= fragile
    end
  end

  def find_variant_for_product(li)
    return nil unless li.product.present? && li.variant_attributes.present?
    li.product.find_variant(li.variant_attributes)
  rescue
    nil
  end

  def select_vehicle_type
    thresholds = settings['vehicle_weight_thresholds'] || DEFAULTS['vehicle_weight_thresholds']
    volume_thresholds = settings['vehicle_volume_thresholds'] || DEFAULTS['vehicle_volume_thresholds']
    refrigerated_capable = settings['vehicle_refrigerated_capable'] || DEFAULTS['vehicle_refrigerated_capable']
    fragile_capable = settings['vehicle_fragile_capable'] || DEFAULTS['vehicle_fragile_capable']

    %w[motorcycle car van truck].each do |type|
      weight_ok = @chargeable_weight <= thresholds[type].to_f
      volume_ok = @volume <= volume_thresholds[type].to_f
      refrigerated_ok = !@refrigerated_needed || refrigerated_capable.include?(type)
      fragile_ok = !@fragile_needed || fragile_capable.include?(type)
      return type if weight_ok && volume_ok && refrigerated_ok && fragile_ok
    end

    'truck'
  end

  def settings
    @settings ||= begin
      stored = Setting.get('logistics_defaults') || {}
      DEFAULTS.deep_merge(stored)
    end
  end
end