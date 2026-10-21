# config/initializers/searchkick.rb
Searchkick.client_options = {
  url: ENV.fetch('OPENSEARCH_URL', 'http://localhost:9200'),
  transport_options: { ssl: { verify: false } }
}