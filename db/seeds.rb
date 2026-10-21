# ============================================================
# LEGAL PAGES – Ethiopian‑compliant, versioned
# ============================================================
puts "Seeding legal pages..."

pages = {
  'terms' => {
    title: 'Terms of Service',
    body: <<~HTML
      <h2>1. Acceptance of Terms</h2>
      <p>By accessing and using the ET Marketplace platform, you agree to be bound by these Terms of Service and all applicable laws and regulations of the Federal Democratic Republic of Ethiopia. If you do not agree with any of these terms, you are prohibited from using this site.</p>

      <h2>2. Platform Role</h2>
      <p>ET Marketplace is a multi‑vendor e‑commerce platform that connects buyers with independent sellers. We are <strong>not</strong> the seller of the products listed. Sellers are solely responsible for the quality, safety, legality, and accuracy of their product listings. We do not deduct VAT or other taxes on behalf of sellers; sellers are independently responsible for their tax obligations under Ethiopian law.</p>

      <h2>3. User Accounts</h2>
      <p>You must provide accurate and complete information when creating an account. You are responsible for maintaining the confidentiality of your account credentials. ET Marketplace reserves the right to suspend or terminate accounts that violate these terms.</p>

      <h2>4. Seller Obligations</h2>
      <ul>
        <li>Sellers must comply with the Ethiopian Commercial Code and all applicable trade regulations.</li>
        <li>Sellers must accept or reject orders within 60 minutes of placement.</li>
        <li>Commission rates are defined per membership plan and are displayed in the seller dashboard.</li>
        <li>Sellers must honour the return policy applicable to the product category.</li>
        <li>Products must not violate Ethiopian import/export restrictions or intellectual property laws.</li>
      </ul>

      <h2>5. Buyer Obligations</h2>
      <ul>
        <li>Buyers must provide accurate delivery information.</li>
        <li>Buyers must pay for orders using approved payment methods.</li>
        <li>Buyers must inspect products upon delivery and report issues within the return window.</li>
      </ul>

      <h2>6. Dispute Resolution</h2>
      <p>Disputes between buyers and sellers will first be mediated by ET Marketplace. If unresolved, disputes shall be settled under the laws of Ethiopia.</p>

      <h2>7. Changes to Terms</h2>
      <p>We reserve the right to modify these terms at any time. Users will be notified of changes and must accept the updated terms to continue using the platform.</p>
    HTML
  },
  'privacy' => {
    title: 'Privacy Policy',
    body: <<~HTML
      <h2>1. Information We Collect</h2>
      <p>We collect personal data including phone number, full name, location data, and delivery addresses. This data is essential for order fulfilment and communication between buyers and sellers.</p>

      <h2>2. How We Use Your Data</h2>
      <ul>
        <li>To facilitate orders and deliveries</li>
        <li>To communicate order updates and marketing messages (with your consent)</li>
        <li>To improve platform safety and prevent fraud</li>
        <li>To comply with Ethiopian law enforcement requests</li>
      </ul>

      <h2>3. Data Sharing</h2>
      <p>We share your delivery address and phone number with sellers and logistics partners solely for order fulfilment. We do not sell personal data to third parties.</p>

      <h2>4. Data Retention</h2>
      <p>Personal data is retained for the duration of your account plus 5 years as required by Ethiopian commercial regulations. You may request account deletion at any time.</p>

      <h2>5. Your Rights</h2>
      <p>Under Ethiopian law, you have the right to access, correct, or delete your personal data. Contact our Data Protection Officer at privacy@etmarketplace.com.</p>
    HTML
  },
  'cookies' => {
    title: 'Cookie Policy',
    body: <<~HTML
      <h2>1. What Are Cookies</h2>
      <p>Cookies are small text files stored on your device when you visit our website. They help us remember your preferences and improve your experience.</p>
      <h2>2. Types of Cookies We Use</h2>
      <ul><li>Essential cookies: required for the platform to function</li><li>Analytics cookies: help us understand usage patterns</li><li>Marketing cookies: used for promotions and advertisements</li></ul>
      <h2>3. Managing Cookies</h2>
      <p>You can disable cookies in your browser settings, but some features may not work properly.</p>
    HTML
  },
  'buyer-protection' => {
    title: 'Buyer Protection',
    body: <<~HTML
      <h2>1. Order Protection Guarantee</h2>
      <p>If your order does not arrive, arrives damaged, or is significantly different from the description, you are entitled to a full refund including delivery charges.</p>
      <h2>2. Return Window</h2>
      <p>The return window is defined per product category and is displayed before purchase. You must submit a return request within this window after delivery.</p>
      <h2>3. Refund Timeline</h2>
      <p>Refunds are processed within 7 business days after the returned item is received and inspected by the seller.</p>
    HTML
  },
  'ip-policy' => {
    title: 'Intellectual Property Policy',
    body: <<~HTML
      <h2>1. Copyright and Trademarks</h2>
      <p>All content on ET Marketplace, including logos, text, and images, is protected by Ethiopian copyright law. Sellers must not list counterfeit or unauthorised products.</p>
      <h2>2. Infringement Claims</h2>
      <p>If you believe your intellectual property rights have been violated, please contact us with evidence at ip@etmarketplace.com. We will investigate and remove infringing content.</p>
    HTML
  },
  'shipping-returns' => {
    title: 'Shipping & Delivery / Returns & Refunds',
    body: <<~HTML
      <h2>1. Delivery</h2>
      <p>Delivery times depend on the seller's location and the logistics partner. Estimated delivery times are displayed at checkout. Delays may occur due to external factors.</p>
      <h2>2. Returns</h2>
      <p>Return policies vary by product category. The applicable return window, restocking fee, and responsibility for return shipping are displayed before purchase and frozen on each order.</p>
      <h2>3. Refunds</h2>
      <p>Refunds are issued to the original payment method (Telebirr, bank, or cash for COD orders). The refund amount may exclude restocking fees and return shipping costs if the buyer is liable.</p>
    HTML
  }
}

pages.each do |key, attrs|
  page = LegalPage.find_or_initialize_by(key: key)
  page.assign_attributes(attrs.merge(published: true, published_at: Time.current))
  page.save!
  puts "  Seeded legal page: #{page.title} (v#{page.version})"
end

# ============================================================
# MAIN CATEGORIES & SUBCATEGORIES
# ============================================================
category_tree = {
  "Electronics" => [
    "Mobile Phones", "Laptops", "Tablets", "Desktops", "Monitors", "Cameras",
    "Audio & Headphones", "Wearable Tech", "TV & Video", "Gaming Consoles",
    "Smart Home Devices", "E-Readers", "Networking Devices"
  ],
  "Fashion" => [
    "Men's Fashion", "Women's Fashion", "Kids' Fashion", "Shoes", "Bags & Luggage",
    "Jewelry", "Watches", "Accessories", "Belts", "Hats & Caps", "Sunglasses"
  ],
  "Home & Kitchen" => [
    "Kitchen", "Furniture", "Bedding & Bath", "Home Decor",
    "Kitchen Appliances", "Cookware & Bakeware", "Home Improvement",
    "Major Appliances", "Small Kitchen Appliances",
    "Dining & Entertaining", "Lighting", "Carpets & Rugs", "Curtains & Blinds"
  ],
  "Sports & Outdoors" => [
    "Fitness Equipment", "Camping & Hiking", "Bikes & Cycling", "Team Sports",
    "Water Sports", "Winter Sports", "Yoga & Pilates", "Golf", "Tennis", "Running"
  ],
  "Beauty & Personal Care" => [
    "Makeup", "Skincare", "Hair Care", "Fragrance", "Bath & Body", "Tools & Accessories"
  ],
  "Health & Wellness" => [
    "Vitamins & Supplements", "Medical Supplies", "Mobility Aids", "Personal Care Devices"
  ],
  "Groceries" => [
    "Snacks", "Beverages", "Fresh Food", "Frozen Food", "Pantry Staples", "Coffee & Tea"
  ],
  "Toys & Games" => [],
  "Baby Products" => ["Baby Feeding", "Diapering", "Nursery"],
  "Pet Supplies" => ["Dog", "Cat", "Fish", "Bird", "Small Pet"],
  "Automotive" => ["Car Parts", "Car Accessories", "Tires & Wheels"],
  "Tools" => ["Power Tools", "Hand Tools", "Tool Storage"],
  "Office Supplies" => ["Stationery", "Filing & Storage"],
  "Musical Instruments" => [],
  "Arts & Crafts" => ["Crafts & Sewing", "Art Supplies", "Fabric"],
  "Books & Media" => ["Books", "Textbooks", "Audiobooks", "E-Books"],
  "Gift Cards" => [],
  "Software" => []
}

category_tree.each do |main_name, subs|
  main_cat = Category.find_or_create_by!(name: main_name)
  subs.each do |sub_name|
    Category.find_or_create_by!(name: sub_name) do |c|
      c.parent = main_cat
    end
  end
end

# ============================================================
# DEMO SELLER USER & VENDOR CREATION – REMOVED
# (previously contained User/Vendor creation, now omitted)
# ============================================================

# ============================================================
# ATTRIBUTE CATALOG (ultra‑extended)
# ============================================================
def find_or_create_attr(name, type:, filterable: true, variant: false, display: nil)
  Attribute.find_or_create_by!(name: name) do |a|
    a.display_name   = display || name.titleize
    a.attr_type      = type
    a.is_filterable  = filterable
    a.is_variant     = variant
  end
end

def add_values(attr_name, values)
  attr = Attribute.find_by!(name: attr_name)
  values.each { |v| attr.attribute_values.find_or_create_by!(value: v) }
end

def assign_to_category(category_name, attr_name, required: false)
  cat  = Category.find_by!(name: category_name)
  attr = Attribute.find_by!(name: attr_name)
  cat.category_attributes.find_or_create_by!(attr: attr) do |ca|
    ca.is_required = required
  end
end

attributes_defs = [
  { name: 'color', type: :dropdown, filterable: true, variant: true, display: 'Color',
    values: %w[Black White Red Blue Green Yellow Orange Pink Purple Brown
               Grey Gray Silver Gold Navy Maroon Beige Teal Turquoise Lavender
               Ivory Charcoal Khaki Magenta Tan Coral Mint Olive Mustard
               Burgundy Rose Gold Bronze Cream Lilac Salmon Indigo] },
  { name: 'size', type: :dropdown, filterable: true, variant: true, display: 'Size',
    values: %w[XS S M L XL XXL 3XL 4XL 5XL One\ Size] },
  { name: 'brand', type: :dropdown, filterable: true, variant: false, display: 'Brand',
    values: [
      'Apple', 'Samsung', 'Sony', 'LG', 'Dell', 'HP', 'Lenovo', 'Asus', 'Acer',
      'Microsoft', 'Google', 'OnePlus', 'Xiaomi', 'Oppo', 'Vivo', 'Huawei', 'Realme',
      'Motorola', 'Nokia', 'ZTE', 'HTC', 'Alcatel', 'BlackBerry', 'Panasonic',
      'Bose', 'JBL', 'Sennheiser', 'Sonos', 'Beats', 'Bowers & Wilkins',
      'Canon', 'Nikon', 'Fujifilm', 'GoPro', 'Olympus', 'Pentax', 'Leica',
      'Garmin', 'Fitbit', 'Polar', 'Suunto', 'Withings', 'Amazfit',
      'Nintendo', 'PlayStation', 'Xbox', 'Oculus', 'Razer', 'Logitech',
      'Epson', 'Brother', 'TP-Link', 'Netgear', 'D-Link', 'Linksys',
      'Nike', 'Adidas', 'Puma', 'Reebok', 'Under Armour', 'New Balance', 'Asics',
      'Converse', 'Vans', 'Skechers', 'Crocs', 'Dr. Martens', 'Timberland',
      'Levi\'s', 'Zara', 'H&M', 'Uniqlo', 'Mango', 'Gap', 'Banana Republic',
      'Ralph Lauren', 'Tommy Hilfiger', 'Calvin Klein', 'Diesel', 'Guess',
      'Gucci', 'Prada', 'Louis Vuitton', 'Chanel', 'Hermès', 'Burberry',
      'Dolce & Gabbana', 'Versace', 'Armani', 'Balenciaga', 'Saint Laurent',
      'Coach', 'Michael Kors', 'Tory Burch', 'Kate Spade', 'Fendi', 'Givenchy',
      'Rolex', 'Casio', 'Timex', 'Seiko', 'Citizen', 'Tissot', 'Omega',
      'Cartier', 'TAG Heuer', 'Breitling',
      'KitchenAid', 'Cuisinart', 'Hamilton Beach', 'Breville', 'Instant Pot',
      'Ninja', 'Philips', 'Dyson', 'iRobot', 'Shark', 'Bissell',
      'Samsung', 'LG', 'Whirlpool', 'GE', 'Frigidaire', 'Electrolux', 'Bosch',
      'Miele', 'Siemens', 'Kenmore', 'Maytag', 'Amana', 'Hotpoint',
      'IKEA', 'Ashley Furniture', 'La-Z-Boy', 'Tempur-Pedic', 'Sealy', 'Serta',
      'Herman Miller', 'Steelcase',
      'The North Face', 'Patagonia', 'Columbia', 'Marmot', 'Arc\'teryx',
      'Salomon', 'Merrell', 'Keen', 'Brooks', 'Hoka One One', 'Saucony',
      'Wilson', 'Spalding', 'Rawlings', 'Easton', 'Callaway', 'Titleist',
      'Ping', 'TaylorMade', 'Coleman', 'Osprey', 'Big Agnes', 'Black Diamond',
      'L\'Oréal', 'Maybelline', 'MAC', 'Clinique', 'Estée Lauder', 'Lancôme',
      'Nivea', 'Dove', 'Neutrogena', 'Cetaphil', 'CeraVe', 'Olay', 'Garnier',
      'Revlon', 'CoverGirl', 'NYX', 'Urban Decay', 'Too Faced', 'Benefit',
      'Philips Norelco', 'Braun', 'Oral-B', 'Gillette', 'Venus', 'Schick',
      'Purina', 'Royal Canin', 'Hill\'s Science Diet', 'Pedigree', 'Whiskas',
      'Blue Buffalo', 'Iams', 'Eukanuba', 'Merrick',
      'Mobil', 'Castrol', 'Valvoline', 'Pennzoil', 'Bosch', 'Michelin', 'Goodyear',
      'Bridgestone', 'Pirelli', 'Continental', 'Monroe', 'KYB',
      'Makita', 'DeWalt', 'Milwaukee', 'Bosch', 'Ryobi', 'Black+Decker',
      'Craftsman', 'Stanley', 'Klein Tools', 'Ridgid', 'Husky',
      'Fender', 'Gibson', 'Yamaha', 'Roland', 'Casio', 'Korg', 'Ibanez',
      'Shure', 'AKG', 'Sennheiser',
      'Staples', 'Swingline', 'Bic', 'Paper Mate', 'Sharpie', 'Pilot', '3M',
      'Fellowes', 'Avery',
      'LEGO', 'Mattel', 'Hasbro', 'Fisher-Price', 'VTech', 'Playmobil',
      'Pampers', 'Huggies', 'Nestlé', 'Gerber', 'Enfamil', 'Similac'
    ].uniq
  },
  { name: 'material', type: :dropdown, filterable: true, variant: false, display: 'Material',
    values: ['Cotton', 'Polyester', 'Wool', 'Silk', 'Linen', 'Denim', 'Leather',
             'Suede', 'Nylon', 'Spandex', 'Rayon', 'Acrylic', 'Cashmere', 'Velvet',
             'Canvas', 'Neoprene', 'Metal', 'Plastic', 'Glass', 'Wood',
             'Stainless Steel', 'Aluminum', 'Titanium', 'Rubber', 'Silicone',
             'Ceramic', 'Porcelain', 'Marble', 'Granite', 'Bamboo', 'Wicker',
             'Rattan', 'Vinyl', 'Faux Fur', 'Fleece', 'Tweed', 'Corduroy'] },
  { name: 'style', type: :dropdown, filterable: true, variant: false, display: 'Style',
    values: %w[Modern Classic Vintage Sport Casual Formal Bohemian Minimalist
               Rustic Industrial Retro Glam Contemporary Traditional Art\ Deco
               Mid-Century Scandinavian] },
  { name: 'pattern', type: :dropdown, filterable: true, variant: false, display: 'Pattern',
    values: ['Solid', 'Striped', 'Checked', 'Floral', 'Camouflage', 'Polka Dot',
             'Paisley', 'Geometric', 'Animal Print', 'Plaid', 'Houndstooth',
             'Ikat', 'Tie-Dye', 'Gingham', 'Herringbone', 'Damask'] },
  { name: 'connectivity', type: :dropdown, filterable: true, variant: false,
    display: 'Connectivity',
    values: ['Wi-Fi', 'Bluetooth', '5G', '4G LTE', 'NFC', 'USB-C', 'USB-A',
             'HDMI', 'Thunderbolt', 'Ethernet', 'GPS', 'Zigbee', 'Z-Wave',
             'Wi-Fi 6', 'Wi-Fi 6E', 'Wi-Fi 7'] },
  { name: 'edition', type: :dropdown, filterable: true, variant: true, display: 'Edition',
    values: %w[Standard Pro Premium Lite Ultra Max Mini Plus Special\ Edition
               Limited\ Edition Signature Collectors] },
  { name: 'storage', type: :dropdown, filterable: true, variant: true, display: 'Storage',
    values: %w[16GB 32GB 64GB 128GB 256GB 512GB 1TB 2TB 4TB 8TB] },
  { name: 'ram', type: :dropdown, filterable: true, variant: true, display: 'RAM',
    values: %w[2GB 4GB 6GB 8GB 12GB 16GB 32GB 64GB] },
  { name: 'processor', type: :dropdown, filterable: true, variant: false,
    display: 'Processor',
    values: ['Intel Core i3', 'Intel Core i5', 'Intel Core i7', 'Intel Core i9',
             'Intel Pentium', 'Intel Celeron', 'AMD Ryzen 3', 'AMD Ryzen 5',
             'AMD Ryzen 7', 'AMD Ryzen 9', 'AMD Athlon', 'Apple M1', 'Apple M2',
             'Apple M3', 'Qualcomm Snapdragon', 'MediaTek Dimensity',
             'Samsung Exynos', 'Google Tensor', 'UNISOC'] },
  { name: 'os', type: :dropdown, filterable: true, variant: false,
    display: 'Operating System',
    values: ['Android', 'iOS', 'Windows 10', 'Windows 11', 'macOS', 'Linux',
             'Chrome OS', 'iPadOS', 'Tizen', 'wearOS'] },
  { name: 'screen_size', type: :dropdown, filterable: true, variant: true,
    display: 'Screen Size',
    values: ['5.4"', '5.8"', '6.1"', '6.3"', '6.5"', '6.7"', '6.8"', '6.9"',
             '7.6"', '8.3"', '10.2"', '10.9"', '11"', '12.4"', '12.9"',
             '13.3"', '14"', '14.2"', '15.6"', '16"', '16.2"', '17.3"',
             '18.4"', '21.5"', '23.8"', '27"', '31.5"', '32"', '34"',
             '40"', '43"', '48"', '50"', '55"', '65"', '70"', '75"', '77"', '83"', '98"'] },
  { name: 'graphics', type: :dropdown, filterable: true, variant: false,
    display: 'Graphics',
    values: ['Integrated', 'NVIDIA GeForce GTX 1650', 'NVIDIA GeForce RTX 3050',
             'RTX 3060', 'RTX 3070', 'RTX 3080', 'RTX 4060', 'RTX 4070', 'RTX 4080',
             'AMD Radeon RX 6600', 'RX 6700', 'RX 6800', 'RX 6950', 'RX 7900',
             'Intel Iris Xe', 'Apple M2 Graphics'] },
  { name: 'camera', type: :text, filterable: false, variant: false, display: 'Camera Specs' },
  { name: 'battery', type: :text, filterable: false, variant: false, display: 'Battery' },
  { name: 'battery_capacity_mah', type: :dropdown, filterable: true, variant: false,
    display: 'Battery (mAh)',
    values: ['2000mAh', '3000mAh', '4000mAh', '4500mAh', '5000mAh', '6000mAh',
             '8000mAh', '10000mAh'] },
  { name: 'refresh_rate', type: :dropdown, filterable: true, variant: true,
    display: 'Refresh Rate',
    values: %w[60Hz 90Hz 120Hz 144Hz 165Hz 240Hz 360Hz] },
  { name: 'screen_type', type: :dropdown, filterable: true, variant: false,
    display: 'Screen Type',
    values: ['LCD', 'LED', 'OLED', 'AMOLED', 'Super AMOLED', 'Dynamic AMOLED',
             'QLED', 'Neo QLED', 'Micro LED', 'IPS', 'VA', 'TN'] },
  { name: 'fit', type: :dropdown, filterable: true, variant: false, display: 'Fit',
    values: %w[Slim Regular Relaxed Loose Oversized Skinny Athletic Tailored
               Straight Carrot Boot Cut Flare] },
  { name: 'gender', type: :dropdown, filterable: true, variant: true, display: 'Gender',
    values: %w[Men Women Kids Unisex Boys Girls Infants Toddlers] },
  { name: 'age_group', type: :dropdown, filterable: true, variant: false,
    display: 'Age Group',
    values: %w[Newborn 0-3\ m 3-6\ m 6-12\ m 12-18\ m 2T 3T 4T 5T
               Toddler Child 8-10\ y 10-12\ y Teen Adult Senior] },
  { name: 'flavor', type: :dropdown, filterable: true, variant: true, display: 'Flavor',
    values: %w[Vanilla Chocolate Strawberry Lemon Mint Orange Raspberry Blueberry
               Coffee Caramel Apple Cinnamon Honey Peach Mango Cherry Coconut
               Banana Watermelon Grape Pineapple Pomegranate Passion\ Fruit] },
  { name: 'power', type: :text, filterable: true, variant: false, display: 'Power' },
  { name: 'compatibility', type: :dropdown, filterable: true, variant: false,
    values: ['iPhone', 'Android', 'Windows', 'Mac', 'PlayStation', 'Xbox',
             'Nintendo Switch', 'PC', 'Universal'] },
  { name: 'resolution', type: :dropdown, filterable: true, variant: false,
    display: 'Resolution',
    values: %w[720p 1080p 1440p 4K 8K] },
  { name: 'scent', type: :dropdown, filterable: true, variant: true, display: 'Scent',
    values: %w[Unscented Floral Citrus Woody Fresh Spicy Fruity Herbal Gourmand
               Aquatic Oriental Green] },
  { name: 'capacity', type: :dropdown, filterable: true, variant: true,
    display: 'Capacity',
    values: %w[250ml 500ml 750ml 1L 2L 5L 10L 20L 50L 100L 200L] },
  { name: 'energy_rating', type: :dropdown, filterable: true, variant: false,
    display: 'Energy Rating',
    values: ['A+++', 'A++', 'A+', 'A', 'B', 'C', 'D'] },
  { name: 'weight', type: :text, filterable: false, variant: false, display: 'Weight' },
  { name: 'shoe_size_us', type: :dropdown, filterable: true, variant: true,
    display: 'Shoe Size (US)',
    values: (4..16).to_a.map(&:to_s) },
  { name: 'shoe_size_uk', type: :dropdown, filterable: true, variant: true,
    display: 'Shoe Size (UK)',
    values: (2..14).to_a.map(&:to_s) },
  { name: 'shoe_size_eu', type: :dropdown, filterable: true, variant: true,
    display: 'Shoe Size (EU)',
    values: (34..50).to_a.map(&:to_s) },
  { name: 'waist', type: :dropdown, filterable: true, variant: true, display: 'Waist',
    values: %w[24 26 28 30 32 34 36 38 40 42 44 46 48 50 52 54 56] },
  { name: 'chest', type: :dropdown, filterable: true, variant: true, display: 'Chest',
    values: %w[32 34 36 38 40 42 44 46 48 50 52 54 56] },
  { name: 'hip', type: :dropdown, filterable: true, variant: true, display: 'Hip',
    values: %w[28 30 32 34 36 38 40 42 44 46 48 50] },
  { name: 'dress_length', type: :dropdown, filterable: true, variant: true,
    display: 'Dress Length',
    values: %w[Mini Midi Maxi Knee-length Above\ Knee Ankle] },
  { name: 'sleeve', type: :dropdown, filterable: true, variant: true,
    display: 'Sleeve Length',
    values: %w[Short Long 3/4 Sleeveless Cap\ Sleeve] },
  { name: 'neck_style', type: :dropdown, filterable: true, variant: false,
    display: 'Neck Style',
    values: %w[Crew V-Neck Polo Collar Turtleneck Henley Scoop Boat\ Neck
               Square\ Neck Sweetheart Off\ Shoulder] },
  { name: 'dress_size', type: :dropdown, filterable: true, variant: true,
    display: 'Dress Size',
    values: %w[0 2 4 6 8 10 12 14 16 18 20 22 24 26] },
  { name: 'jeans_size', type: :dropdown, filterable: true, variant: true,
    display: 'Jeans Size',
    values: %w[24x30 25x30 26x30 27x34 28x30 29x30 30x32 31x34 32x32 33x34
               34x32 36x34 38x34 40x34 42x34 44x34] },
  { name: 'ring_size', type: :dropdown, filterable: true, variant: true,
    display: 'Ring Size',
    values: (4..13).to_a.map(&:to_s) },
  { name: 'dimensions', type: :text, filterable: false, variant: false, display: 'Dimensions' },
  { name: 'room', type: :dropdown, filterable: true, variant: false, display: 'Room',
    values: %w[Living Bedroom Kitchen Bathroom Office Outdoor Dining\ Room
               Nursery Hallway Garage] },
  { name: 'care', type: :dropdown, filterable: true, variant: false,
    display: 'Care Instructions',
    values: ['Machine Wash', 'Hand Wash', 'Dry Clean Only', 'Spot Clean',
             'Machine Washable', 'Dishwasher Safe', 'Microwave Safe'] },
  { name: 'closure', type: :dropdown, filterable: true, variant: false,
    display: 'Closure Type',
    values: ['Zipper', 'Button', 'Snap', 'Hook & Loop', 'Elastic', 'Pull-On',
             'Drawstring', 'Buckle', 'Magnetic', 'Lace Up'] },
  { name: 'occasion', type: :dropdown, filterable: true, variant: false,
    display: 'Occasion',
    values: %w[Casual Formal Party Office Workout Beach Wedding Vacation School Festival] },
  { name: 'sport', type: :dropdown, filterable: true, variant: false, display: 'Sport',
    values: %w[Running Soccer Basketball Tennis Golf Baseball Football
               Swimming Yoga Cycling Hiking Skiing Snowboarding Skateboarding] },
  { name: 'condition', type: :dropdown, filterable: true, variant: false,
    display: 'Condition',
    values: ['New', 'Like New', 'Used', 'Refurbished', 'Certified Refurbished'] },
  { name: 'warranty', type: :dropdown, filterable: true, variant: false,
    display: 'Warranty',
    values: ['No Warranty', '30 Days', '6 Months', '1 Year', '2 Years',
             '3 Years', '5 Years', 'Lifetime'] },
  { name: 'country_of_origin', type: :dropdown, filterable: true, variant: false,
    display: 'Country of Origin',
    values: ['USA', 'China', 'India', 'Germany', 'Japan', 'South Korea',
             'Italy', 'France', 'UK', 'Canada', 'Mexico', 'Vietnam', 'Indonesia',
             'Bangladesh', 'Turkey', 'Pakistan', 'Thailand', 'Brazil', 'Australia'] },
  { name: 'model_year', type: :dropdown, filterable: true, variant: false,
    display: 'Model Year',
    values: (2015..2026).to_a.map(&:to_s) },
  { name: 'seat_height', type: :dropdown, filterable: true, variant: true,
    display: 'Seat Height',
    values: %w[16" 18" 20" 22" 24" 26" 28" 30"] },
  { name: 'frame_material', type: :dropdown, filterable: true, variant: false,
    display: 'Frame Material',
    values: ['Aluminum', 'Carbon Fiber', 'Steel', 'Titanium', 'Chromoly'] },
  { name: 'skin_type', type: :dropdown, filterable: true, variant: false,
    display: 'Skin Type',
    values: %w[Normal Oily Dry Combination Sensitive Acne-Prone] },
  { name: 'hair_type', type: :dropdown, filterable: true, variant: false,
    display: 'Hair Type',
    values: %w[Straight Wavy Curly Coily Frizz\ Prone Color\ Treated] },
  { name: 'product_type', type: :dropdown, filterable: true, variant: false,
    display: 'Product Type',
    values: ['T-Shirt', 'Shirt', 'Jeans', 'Jacket', 'Hoodie', 'Dress', 'Skirt',
             'Shorts', 'Pants', 'Sweater', 'Sweatshirt', 'Coat', 'Blazer',
             'Vest', 'Swimwear', 'Lingerie', 'Socks', 'Underwear',
             'Smartphone', 'Laptop', 'Tablet', 'Smartwatch', 'Headphones',
             'Earbuds', 'Speaker', 'Camera', 'Lens', 'Printer', 'Monitor',
             'Refrigerator', 'Oven', 'Cooktop', 'Dishwasher', 'Washing Machine',
             'Dryer', 'Microwave', 'Blender', 'Mixer', 'Toaster', 'Vacuum',
             'Sofa', 'Bed', 'Desk', 'Chair', 'Table', 'Lamp',
             'Bag', 'Wallet', 'Sunglasses', 'Hat', 'Belt', 'Necklace', 'Ring'] },
]

attributes_defs.each do |defn|
  attr = find_or_create_attr(defn[:name], type: defn[:type],
                             filterable: defn[:filterable],
                             variant: defn[:variant],
                             display: defn[:display])
  add_values(defn[:name], defn[:values]) if defn[:values]
end

category_attributes_map = {
  "Mobile Phones" => [
    { name: 'brand', required: true }, { name: 'color', required: true, variant: true },
    { name: 'storage', required: true, variant: true }, { name: 'ram', required: false },
    { name: 'screen_size', required: false, variant: true }, { name: 'processor', required: false },
    { name: 'os', required: true }, { name: 'connectivity', required: false },
    { name: 'edition', required: false, variant: true }, { name: 'camera', required: false },
    { name: 'battery_capacity_mah', required: false }, { name: 'screen_type', required: false },
    { name: 'refresh_rate', required: false, variant: true },
    { name: 'condition', required: false }, { name: 'warranty', required: false }
  ],
  "Laptops" => [
    { name: 'brand', required: true }, { name: 'processor', required: true },
    { name: 'ram', required: true, variant: true }, { name: 'storage', required: true, variant: true },
    { name: 'screen_size', required: true, variant: true }, { name: 'os', required: true },
    { name: 'color', required: false, variant: true }, { name: 'graphics', required: false },
    { name: 'battery_capacity_mah', required: false }, { name: 'screen_type', required: false },
    { name: 'edition', required: false }
  ],
  "Tablets" => [
    { name: 'brand', required: true }, { name: 'storage', required: true, variant: true },
    { name: 'ram', required: false }, { name: 'screen_size', required: true, variant: true },
    { name: 'os', required: true }, { name: 'color', required: false, variant: true },
    { name: 'connectivity', required: false }, { name: 'edition', required: false }
  ],
  "Desktops" => [
    { name: 'brand', required: true }, { name: 'processor', required: true },
    { name: 'ram', required: true, variant: true }, { name: 'storage', required: true, variant: true },
    { name: 'graphics', required: false }, { name: 'os', required: true },
    { name: 'dimensions', required: false }
  ],
  "Monitors" => [
    { name: 'brand', required: true }, { name: 'screen_size', required: true, variant: true },
    { name: 'resolution', required: true }, { name: 'refresh_rate', required: true, variant: true },
    { name: 'screen_type', required: true }, { name: 'connectivity', required: false }
  ],
  "Cameras" => [
    { name: 'brand', required: true }, { name: 'megapixels', required: true, variant: true },
    { name: 'lens_type', required: false }, { name: 'connectivity', required: false },
    { name: 'color', required: false, variant: true }
  ],
  "Audio & Headphones" => [
    { name: 'brand', required: true }, { name: 'connectivity', required: true },
    { name: 'color', required: false, variant: true }, { name: 'noise_cancellation', required: false },
    { name: 'edition', required: false }
  ],
  "Wearable Tech" => [
    { name: 'brand', required: true }, { name: 'color', required: true, variant: true },
    { name: 'connectivity', required: false }, { name: 'edition', required: false },
    { name: 'screen_size', required: false, variant: true }
  ],
  "TV & Video" => [
    { name: 'brand', required: true }, { name: 'screen_size', required: true, variant: true },
    { name: 'resolution', required: true }, { name: 'screen_type', required: false },
    { name: 'connectivity', required: false }
  ],
  "Gaming Consoles" => [
    { name: 'brand', required: true }, { name: 'storage', required: true, variant: true },
    { name: 'edition', required: false, variant: true }, { name: 'compatibility', required: false }
  ],
  "Men's Fashion" => [
    { name: 'brand', required: false }, { name: 'size', required: true, variant: true },
    { name: 'color', required: true, variant: true }, { name: 'material', required: false },
    { name: 'style', required: false }, { name: 'pattern', required: false },
    { name: 'fit', required: false }, { name: 'sleeve', required: false, variant: true },
    { name: 'neck_style', required: false }, { name: 'waist', required: false, variant: true },
    { name: 'chest', required: false, variant: true }, { name: 'closure', required: false },
    { name: 'occasion', required: false }, { name: 'product_type', required: false }
  ],
  "Women's Fashion" => [
    { name: 'brand', required: false }, { name: 'size', required: true, variant: true },
    { name: 'color', required: true, variant: true }, { name: 'material', required: false },
    { name: 'style', required: false }, { name: 'pattern', required: false },
    { name: 'fit', required: false }, { name: 'dress_length', required: false, variant: true },
    { name: 'sleeve', required: false, variant: true }, { name: 'waist', required: false, variant: true },
    { name: 'chest', required: false, variant: true }, { name: 'hip', required: false, variant: true },
    { name: 'neck_style', required: false }, { name: 'occasion', required: false },
    { name: 'product_type', required: false }, { name: 'dress_size', required: false, variant: true }
  ],
  "Kids' Fashion" => [
    { name: 'brand', required: false }, { name: 'size', required: true, variant: true },
    { name: 'color', required: true, variant: true }, { name: 'material', required: false },
    { name: 'gender', required: true, variant: true }, { name: 'age_group', required: false },
    { name: 'pattern', required: false }
  ],
  "Shoes" => [
    { name: 'brand', required: true }, { name: 'shoe_size_us', required: true, variant: true },
    { name: 'shoe_size_uk', required: false }, { name: 'shoe_size_eu', required: false },
    { name: 'color', required: true, variant: true }, { name: 'material', required: false },
    { name: 'style', required: false }, { name: 'gender', required: false, variant: true },
    { name: 'sport', required: false }, { name: 'occasion', required: false }
  ],
  "Bags & Luggage" => [
    { name: 'brand', required: false }, { name: 'material', required: true },
    { name: 'color', required: true, variant: true }, { name: 'capacity', required: false, variant: true },
    { name: 'style', required: false }, { name: 'gender', required: false },
    { name: 'product_type', required: false }
  ],
  "Jewelry" => [
    { name: 'material', required: true }, { name: 'color', required: false },
    { name: 'style', required: false }, { name: 'gender', required: false, variant: true },
    { name: 'occasion', required: false }, { name: 'ring_size', required: false, variant: true }
  ],
  "Watches" => [
    { name: 'brand', required: true }, { name: 'band_material', required: false },
    { name: 'movement', required: false }, { name: 'water_resistance', required: false },
    { name: 'color', required: false, variant: true }, { name: 'style', required: false },
    { name: 'gender', required: false, variant: true }, { name: 'edition', required: false }
  ],
  "Accessories" => [
    { name: 'brand', required: false }, { name: 'color', required: true, variant: true },
    { name: 'material', required: false }, { name: 'style', required: false },
    { name: 'gender', required: false }
  ],
  "Kitchen" => [
    { name: 'brand', required: false }, { name: 'color', required: false, variant: true },
    { name: 'material', required: false }, { name: 'capacity', required: false, variant: true },
    { name: 'power', required: false }, { name: 'energy_rating', required: false }
  ],
  "Home & Kitchen" => [
    { name: 'brand', required: false }, { name: 'material', required: false },
    { name: 'color', required: false, variant: true }, { name: 'style', required: false },
    { name: 'room', required: false }, { name: 'dimensions', required: false }
  ],
  "Furniture" => [
    { name: 'brand', required: false }, { name: 'material', required: true },
    { name: 'color', required: true, variant: true }, { name: 'style', required: true },
    { name: 'room', required: false }, { name: 'dimensions', required: true },
    { name: 'weight', required: false }, { name: 'assembly', required: false }
  ],
  "Bedding & Bath" => [
    { name: 'material', required: true }, { name: 'color', required: true, variant: true },
    { name: 'size', required: true, variant: true }, { name: 'pattern', required: false },
    { name: 'care', required: false }
  ],
  "Home Decor" => [
    { name: 'material', required: false }, { name: 'color', required: true, variant: true },
    { name: 'style', required: true }, { name: 'room', required: false }
  ],
  "Kitchen Appliances" => [
    { name: 'brand', required: true }, { name: 'color', required: false, variant: true },
    { name: 'power', required: false }, { name: 'capacity', required: false, variant: true },
    { name: 'energy_rating', required: false }, { name: 'connectivity', required: false }
  ],
  "Cookware & Bakeware" => [
    { name: 'brand', required: false }, { name: 'material', required: true },
    { name: 'color', required: false, variant: true }, { name: 'capacity', required: false, variant: true }
  ],
  "Major Appliances" => [
    { name: 'brand', required: true }, { name: 'capacity', required: true, variant: true },
    { name: 'energy_rating', required: true }, { name: 'color', required: false, variant: true },
    { name: 'dimensions', required: false }
  ],
  "Small Kitchen Appliances" => [
    { name: 'brand', required: true }, { name: 'power', required: false },
    { name: 'color', required: false, variant: true }, { name: 'capacity', required: false }
  ],
  "Sports & Outdoors" => [
    { name: 'brand', required: true }, { name: 'color', required: true, variant: true },
    { name: 'size', required: false, variant: true }, { name: 'material', required: false },
    { name: 'gender', required: false, variant: true }, { name: 'sport', required: false },
    { name: 'condition', required: false }
  ],
  "Fitness Equipment" => [
    { name: 'brand', required: true }, { name: 'material', required: false },
    { name: 'weight', required: false }, { name: 'dimensions', required: false },
    { name: 'condition', required: false }
  ],
  "Camping & Hiking" => [
    { name: 'brand', required: true }, { name: 'material', required: true },
    { name: 'color', required: true, variant: true }, { name: 'capacity', required: false, variant: true },
    { name: 'weight', required: false }
  ],
  "Bikes & Cycling" => [
    { name: 'brand', required: true }, { name: 'frame_material', required: true },
    { name: 'color', required: true, variant: true }, { name: 'size', required: true, variant: true },
    { name: 'gender', required: false }
  ],
  "Team Sports" => [
    { name: 'brand', required: true }, { name: 'size', required: true, variant: true },
    { name: 'color', required: true, variant: true }, { name: 'material', required: false }
  ],
  "Water Sports" => [
    { name: 'brand', required: true }, { name: 'size', required: true, variant: true },
    { name: 'color', required: true, variant: true }, { name: 'material', required: false }
  ],
  "Yoga & Pilates" => [
    { name: 'brand', required: false }, { name: 'material', required: false },
    { name: 'color', required: true, variant: true }, { name: 'thickness', required: false }
  ],
  "Running" => [
    { name: 'brand', required: true }, { name: 'shoe_size_us', required: true, variant: true },
    { name: 'color', required: true, variant: true }, { name: 'gender', required: false, variant: true },
    { name: 'terrain', required: false }
  ],
  "Beauty & Personal Care" => [
    { name: 'brand', required: true }, { name: 'product_type', required: false },
    { name: 'skin_type', required: false }, { name: 'scent', required: false, variant: true },
    { name: 'color', required: false, variant: true }, { name: 'size', required: false, variant: true }
  ],
  "Skincare" => [
    { name: 'brand', required: true }, { name: 'skin_type', required: true },
    { name: 'scent', required: false, variant: true }, { name: 'size', required: true, variant: true }
  ],
  "Hair Care" => [
    { name: 'brand', required: true }, { name: 'hair_type', required: false },
    { name: 'scent', required: false }, { name: 'size', required: true, variant: true }
  ],
  "Makeup" => [
    { name: 'brand', required: true }, { name: 'color', required: true, variant: true },
    { name: 'finish', required: false }, { name: 'product_type', required: false }
  ],
  "Groceries" => [
    { name: 'brand', required: false }, { name: 'flavor', required: false, variant: true },
    { name: 'size', required: true, variant: true }, { name: 'capacity', required: false, variant: true },
    { name: 'weight', required: false }
  ],
  "Toys & Games" => [
    { name: 'brand', required: true }, { name: 'age_group', required: true },
    { name: 'material', required: false }, { name: 'color', required: false, variant: true }
  ],
  "Baby Products" => [
    { name: 'brand', required: true }, { name: 'age_group', required: true },
    { name: 'color', required: false, variant: true }, { name: 'material', required: false }
  ],
  "Pets Supplies" => [
    { name: 'brand', required: true }, { name: 'flavor', required: false, variant: true },
    { name: 'size', required: true, variant: true }, { name: 'material', required: false }
  ],
  "Automotive" => [
    { name: 'brand', required: true }, { name: 'compatibility', required: true },
    { name: 'material', required: false }, { name: 'capacity', required: false }
  ],
  "Tools" => [
    { name: 'brand', required: true }, { name: 'power_source', required: false },
    { name: 'material', required: false }, { name: 'size', required: false, variant: true }
  ],
  "Office Supplies" => [
    { name: 'brand', required: false }, { name: 'color', required: true, variant: true },
    { name: 'material', required: false }
  ],
  "Musical Instruments" => [
    { name: 'brand', required: true }, { name: 'material', required: false },
    { name: 'color', required: true, variant: true }, { name: 'size', required: false, variant: true }
  ],
  "Crafts & Sewing" => [
    { name: 'material', required: true }, { name: 'color', required: true, variant: true },
    { name: 'size', required: false, variant: true }
  ],
  "Books" => [
    { name: 'edition', required: false }, { name: 'format', required: false },
    { name: 'author', required: false }, { name: 'publication_year', required: false }
  ]
}

additional_attrs = {
  'megapixels' => { type: :dropdown, values: %w[12MP 16MP 20MP 24MP 36MP 45MP 50MP 61MP 100MP] },
  'lens_type' => { type: :dropdown, values: %w[Prime Zoom Macro Wide-Angle Telephoto Fisheye] },
  'noise_cancellation' => { type: :dropdown, values: %w[Active Passive None] },
  'water_resistance' => { type: :dropdown, values: ['IPX4', 'IPX7', 'IP68', 'Waterproof 50m', 'Not water resistant'] },
  'power_source' => { type: :dropdown, values: %w[Battery Electric Manual Solar Gas] },
  'finish' => { type: :dropdown, values: %w[Matte Glossy Satin Brushed Polished] },
  'band_material' => { type: :dropdown, values: %w[Leather Metal Resin Fabric Silicone] },
  'movement' => { type: :dropdown, values: %w[Quartz Automatic Mechanical Solar] },
  'assembly' => { type: :text, values: nil },
  'thickness' => { type: :dropdown, values: %w[1mm 2mm 3mm 4mm 5mm 6mm 8mm 10mm] },
  'terrain' => { type: :dropdown, values: %w[Road Trail Track Indoor All\ Terrain] },
  'format' => { type: :dropdown, values: %w[Hardcover Paperback Board\ Book E-Book Audiobook] },
  'author' => { type: :text, values: nil },
  'publication_year' => { type: :dropdown, values: (2000..2026).to_a.map(&:to_s) }
}

additional_attrs.each do |name, attr_info|
  unless Attribute.exists?(name: name)
    find_or_create_attr(name, type: attr_info[:type], filterable: true, variant: false)
    add_values(name, attr_info[:values]) if attr_info[:values]
  end
end

category_attributes_map.each do |cat_name, attrs|
  next unless Category.exists?(name: cat_name)
  attrs.each do |a|
    assign_to_category(cat_name, a[:name], required: a[:required] || false)
  end
end

puts "Ultra-extended attribute catalog seeded successfully with category hierarchy!"