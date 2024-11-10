class WatchlistItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_watchlist_item, only: [:destroy, :toggle_watched, :reposition]
  after_action :verify_authorized, except: [:index, :status, :count]
  after_action :verify_policy_scoped, only: :index

  def index
    base_items = policy_scope(WatchlistItem).order(:position)
    @watchlist_items = base_items.map do |item|
      content = Content.find_by(source_id: item.source_id, content_type: item.content_type)
      next unless content

      {
        id: item.id,
        source_id: item.source_id,
        content_type: item.content_type,
        title: content.title,
        poster_url: content.poster_url,
        release_year: content.release_year,
        vote_average: content.vote_average,
        genres: content.genre_names,
        country: content.production_countries_array&.first&.dig('name'),
        watched: item.watched,
        rating: item.rating
      }
    end.compact
    
    @watched_items = @watchlist_items.select { |item| item[:watched] }
    @unwatched_items = @watchlist_items.reject { |item| item[:watched] }
  end

  def create
    @content = Content.find_by(
      source_id: params.dig(:watchlist_item, :source_id),
      content_type: params.dig(:watchlist_item, :content_type)
    )
    
    if @content.nil?
      render json: { status: 'error', message: 'Content not found' }, status: :not_found
      return
    end

    WatchlistItem.transaction do
      # Increment positions of existing unwatched items
      current_user.watchlist_items
                 .where(watched: false)
                 .update_all('position = position + 1')
      
      # Create new item at position 1
      @watchlist_item = current_user.watchlist_items.new(watchlist_item_params)
      @watchlist_item.position = 1
      authorize @watchlist_item
      
      if @watchlist_item.save
        render json: { 
          status: 'success', 
          in_watchlist: true, 
          watched: @watchlist_item.watched, 
          rating: @watchlist_item.rating,
          item: item_with_details(@watchlist_item)
        }
      else
        render json: { 
          status: 'error', 
          message: @watchlist_item.errors.full_messages.join(', ') 
        }, status: :unprocessable_entity
      end
    end
  end

  def destroy
    authorize @watchlist_item
    @watchlist_item.destroy
    render json: { status: 'success', message: 'Item removed from watchlist' }
  rescue ActiveRecord::RecordNotFound
    render json: { status: 'error', message: 'Item not found in watchlist' }, status: :not_found
  end

  def status
    Rails.logger.debug "Status params: #{params.inspect}"
    item = current_user.watchlist_items.find_by(source_id: params[:source_id], content_type: params[:content_type])
    Rails.logger.debug "Found item: #{item.inspect}"
    render json: {
      in_watchlist: item.present?,
      watched: item&.watched || false,
      rating: item&.rating
    }
  end

  def count
    Rails.logger.debug "Count action called"
    count = current_user.watchlist_items.count
    Rails.logger.debug "Watchlist count: #{count}"
    render json: { count: count }
  end

  def recent
    authorize WatchlistItem
    items = current_user.watchlist_items
                       .where(watched: false)
                       .order(created_at: :desc)
                       .limit(5)
                       .map { |item| item_with_details(item) }
                       .compact
    
    render json: { items: items }
  end

  def reposition
    authorize @watchlist_item
    
    new_position = params.dig(:watchlist_item, :position)
    watched_status = params.dig(:watchlist_item, :watched)
    
    WatchlistItem.transaction do
      old_position = @watchlist_item.position
      old_watched_status = @watchlist_item.watched
      
      if old_watched_status == watched_status
        # Moving within same list - reorder all items to ensure no gaps
        items = current_user.watchlist_items.where(watched: watched_status).order(:position)
        items_array = items.to_a
        moved_item = items_array.delete(@watchlist_item)
        items_array.insert(new_position - 1, moved_item)
        
        # Update all positions sequentially
        items_array.each_with_index do |item, index|
          item.update_column(:position, index + 1)
        end
      else
        # Moving between lists - similar to current code but with sequential reordering
        # Update old list positions
        old_list_items = current_user.watchlist_items
          .where(watched: old_watched_status)
          .where('position > ?', old_position)
          .order(:position)
        
        old_list_items.each_with_index do |item, index|
          item.update_column(:position, old_position + index)
        end
        
        # Update new list positions
        new_list_items = current_user.watchlist_items
          .where(watched: watched_status)
          .order(:position)
        
        @watchlist_item.update!(watched: watched_status)
        @watchlist_item.insert_at(new_position)
      end
    end
    
    render json: { status: 'success' }
  rescue ActiveRecord::RecordNotFound
    render json: { status: 'error', message: 'Item not found' }, status: :not_found
  end

  def toggle_watched
    authorize @watchlist_item
    new_watched_state = !@watchlist_item.watched
    
    WatchlistItem.transaction do
      # Move other items down in the target section
      current_user.watchlist_items
                 .where(watched: new_watched_state)
                 .update_all('position = position + 1')
      
      # Update the item and move it to position 1 in its new section
      if new_watched_state
        @watchlist_item.update(watched: true, position: 1)
      else
        @watchlist_item.update(watched: false, rating: nil, position: 1)
      end
    end
    
    render json: { 
      status: 'success', 
      in_watchlist: true, 
      watched: @watchlist_item.watched, 
      rating: @watchlist_item.rating 
    }
  end

  def rate
    @watchlist_item = current_user.watchlist_items.find_by!(
      source_id: params.dig(:watchlist_item, :source_id),
      content_type: params.dig(:watchlist_item, :content_type)
    )
    authorize @watchlist_item

    rating = params.dig(:watchlist_item, :rating)
    
    if rating.present?
      if @watchlist_item.update(rating: rating, watched: true)
        render json: { status: 'success', rating: @watchlist_item.rating }
      else
        render json: { 
          status: 'error', 
          message: @watchlist_item.errors.full_messages.join(', ') 
        }, status: :unprocessable_entity
      end
    else
      render json: { 
        status: 'error', 
        message: 'Rating cannot be empty' 
      }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: { status: 'error', message: 'Item not found in watchlist' }, status: :not_found
  end

  def unwatched_count
    authorize WatchlistItem
    count = policy_scope(WatchlistItem).where(watched: false).count
    Rails.logger.debug "Unwatched count: #{count}"
    render json: { count: count }
  end

  private

  def watchlist_item_params
    params.require(:watchlist_item).permit(:source_id, :content_type, :rating, :watched)
  end

  def item_with_details(item)
    content = Content.find_by(source_id: item.source_id, content_type: item.content_type)
    return nil unless content

    {
      id: item.id,
      source_id: item.source_id,
      content_type: item.content_type,
      watched: item.watched,
      title: content.title,
      poster_url: content.poster_url,
      release_year: content.release_year,
      production_countries: content.production_countries_array&.first&.dig('name'),
      vote_average: content.vote_average,
      genres: content.genre_names
    }
  end

  def set_watchlist_item
    @watchlist_item = current_user.watchlist_items.find_by!(
      source_id: params[:id],
      content_type: params.dig(:watchlist_item, :content_type) || params[:content_type]
    )
  end

  def watchlist_params
    params.require(:watchlist_item).permit(:position, :content_type, :watched)
  end
end
