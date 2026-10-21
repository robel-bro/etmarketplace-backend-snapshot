module Api
  module V1
    class SavedSearchesController < ApplicationController
      include Authentication
      before_action :require_authentication

      def index
        searches = current_user.saved_searches.order(created_at: :desc).limit(20)
        render json: searches.map { |s| { id: s.id, query: s.query, created_at: s.created_at } }
      end

      def create
        # Upsert – if the same query exists, touch it; otherwise create a new one
        search = current_user.saved_searches.find_or_initialize_by(query: params[:query].strip.downcase)
        search.touch if search.persisted?
        search.save!
        head :ok
      end

      def destroy
        current_user.saved_searches.find(params[:id]).destroy
        head :no_content
      end
    end
  end
end