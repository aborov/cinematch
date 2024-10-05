class WatchlistItemsController < ApplicationController
  before_action :authenticate_user!
  after_action :verify_authorized, except: [:index, :status, :count, :recent]
  after_action :verify_policy_scoped, only: :index

  def index
    @watchlist_items = policy_scope(WatchlistItem)
    @unwatched_items = @watchlist_items.unwatched
    @watched_items = @watchlist_items.watched
  end

  def create
    content = Content.find_by(source_id: params[:source_id], content_type: params[:content_type])
    @watchlist_item = current_user.watchlist_items.find_or_initialize_by(source_id: content.source_id, content_type: content.content_type)
    authorize @watchlist_item

    if @watchlist_item.persisted? || @watchlist_item.save
      render json: { 
        status: 'success', 
        message: 'Item added to watchlist', 
        in_watchlist: true, 
        content_id: content.source_id,
        count: current_user.watchlist_items.count
      }
    else
      render json: { status: 'error', message: 'Failed to add item to watchlist', errors: @watchlist_item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @watchlist_item = current_user.watchlist_items.find_by(source_id: params[:id], content_type: params[:content_type])
    if @watchlist_item
      authorize @watchlist_item
      if @watchlist_item.destroy
        render json: { 
          status: 'success', 
          message: 'Item removed from watchlist',
          content_id: params[:id],
          content_type: params[:content_type],
          count: current_user.watchlist_items.count
        }
      else
        render json: { status: 'error', message: 'Failed to remove item from watchlist' }, status: :unprocessable_entity
      end
    else
      skip_authorization
      render json: { status: 'error', message: 'Item not found in watchlist' }, status: :not_found
    end
  end

  def mark_watched
    content = Content.find_by(source_id: params[:id])
    @watchlist_item = current_user.watchlist_items.find_by(source_id: params[:id], content_type: params[:content_type])
    authorize @watchlist_item, :mark_watched?
    if @watchlist_item.update(watched: true)
      render json: { 
        status: 'success', 
        message: 'Item marked as watched', 
        content_id: content.source_id,
        count: current_user.watchlist_items.count
      }
    else
      render json: { status: 'error', message: 'Failed to mark item as watched' }, status: :unprocessable_entity
    end
  end

  def mark_unwatched
    content = Content.find_by(source_id: params[:id], content_type: params[:content_type])
    @watchlist_item = current_user.watchlist_items.find_by(source_id: params[:id], content_type: params[:content_type])
    authorize @watchlist_item, :mark_unwatched?
    if @watchlist_item.update(watched: false)
      render json: { 
        status: 'success', 
        message: 'Item marked as unwatched', 
        source_id: content.source_id,
        count: current_user.watchlist_items.count
      }
    else
      render json: { status: 'error', message: 'Failed to mark item as unwatched' }, status: :unprocessable_entity
    end
  end

  def status
    content = Content.find_by(source_id: params[:source_id], content_type: params[:content_type])
    authorize :watchlist_item, :status?
    in_watchlist = current_user.watchlist_items.exists?(source_id: params[:source_id], content_type: params[:content_type])
    render json: { in_watchlist: in_watchlist }
  end

  def count
    count = current_user.watchlist_items.count
    render json: { count: count }
  end

  def recent
    items = current_user.watchlist_items.order(created_at: :desc).limit(5).map do |item|
      content = item.content
      { title: content.title, year: content.release_year, poster_url: content.poster_url }
    end
    render json: { items: items }
  rescue => e
    Rails.logger.error "Error in recent action: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { error: 'An error occurred while fetching recent items' }, status: :internal_server_error
  end

  private

  def watchlist_item_params
    params.require(:watchlist_item).permit(:content_id, :content_type)
  end
end
