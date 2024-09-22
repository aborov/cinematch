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
    content = Content.find_by(source_id: params[:content_id], content_type: params[:content_type])
    @watchlist_item = current_user.watchlist_items.find_or_initialize_by(content: content)
    authorize @watchlist_item

    if @watchlist_item.persisted? || @watchlist_item.save
      render json: { status: 'success', message: 'Item added to watchlist', in_watchlist: true }
    else
      render json: { status: 'error', message: 'Failed to add item to watchlist', errors: @watchlist_item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    content = Content.find_by(source_id: params[:id])
    @watchlist_item = current_user.watchlist_items.find_by(content: content)

    if @watchlist_item
      authorize @watchlist_item
      if @watchlist_item.destroy
        render json: { 
          status: 'success', 
          message: 'Item removed from watchlist', 
          in_watchlist: false, 
          content_id: content.source_id,
          count: current_user.watchlist_items.count
        }
      else
        render json: { status: 'error', message: 'Failed to remove item from watchlist' }, status: :unprocessable_entity
      end
    else
      skip_authorization
      render json: { status: 'error', message: 'Watchlist item not found' }, status: :not_found
    end
  end

  def mark_watched
    content = Content.find_by(source_id: params[:id])
    @watchlist_item = current_user.watchlist_items.find_by(content: content)
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
    content = Content.find_by(source_id: params[:id])
    @watchlist_item = current_user.watchlist_items.find_by(content: content)
    authorize @watchlist_item, :mark_unwatched?
    if @watchlist_item.update(watched: false)
      render json: { 
        status: 'success', 
        message: 'Item marked as unwatched', 
        content_id: content.source_id,
        count: current_user.watchlist_items.count
      }
    else
      render json: { status: 'error', message: 'Failed to mark item as unwatched' }, status: :unprocessable_entity
    end
  end

  def status
    content = Content.find_by(source_id: params[:content_id], content_type: params[:content_type])
    authorize :watchlist_item, :status?
    in_watchlist = current_user.watchlist_items.exists?(content: content)
    render json: { in_watchlist: in_watchlist }
  end

  def count
    count = current_user.watchlist_items.count
    render json: { count: count }
  end

  def recent
    items = current_user.watchlist_items.order(created_at: :desc).limit(5).includes(:content).map do |item|
      { title: item.content.title, year: item.content.release_year, poster_url: item.content.poster_url }
    end
    render json: { items: items }
  end

  private

  def watchlist_item_params
    params.require(:watchlist_item).permit(:content_id, :content_type)
  end
end
