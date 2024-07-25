$(document).on('turbolinks:load', function() {
  $(document).on('click', '.show-details', function(e) {
    e.preventDefault();
    var id = $(this).data('id');
    var type = $(this).data('type');
    showDetails(id, type);
  });

  $(document).on('click', '.close-button', function() {
    closePopup();
  });
  
  window.showDetails = function(id, type) {
    $.ajax({
      url: `/recommendations/${id}?type=${type}`,
      method: 'GET',
      dataType: 'json',
      success: function(data) {
        var runtime = data.runtime || (data.episode_run_time ? data.episode_run_time[0] : 'N/A');
        var releaseYear = (data.release_date || data.first_air_date || '').substring(0, 4);
        var countries = data.production_countries ? data.production_countries.map(c => c.name).join(', ') : 'N/A';
        var directors = data.credits && data.credits.crew ? data.credits.crew.filter(c => c.job === 'Director').map(d => d.name).join(', ') : 'N/A';
        var cast = data.credits && data.credits.cast ? data.credits.cast.slice(0, 5).map(c => c.name).join(', ') : 'N/A';
        var videoKey = data.videos && data.videos.results[0] ? data.videos.results[0].key : '';

        var details = `
          <div class="popup-details">
            <img src="https://image.tmdb.org/t/p/w500${data.poster_path}" alt="${data.title || data.name}" />
            <div class="info">
              <h2>${data.title || data.name}</h2>
              <p><strong>Runtime:</strong> ${runtime} minutes</p>
              <p><strong>Release Year:</strong> ${releaseYear}</p>
              <p><strong>Country:</strong> ${countries}</p>
              <p><strong>Description:</strong> ${data.overview}</p>
              <p><strong>Director(s):</strong> ${directors}</p>
              <p><strong>Cast:</strong> ${cast}</p>
              <iframe width="100%" height="315" src="https://www.youtube.com/embed/${videoKey}" frameborder="0" allowfullscreen></iframe>
            </div>
          </div>
        `;
        $('#popup-details').html(details);
        $('#popup').show();

        // Adjust the popup height to fit all content
        var popupContent = document.querySelector('.popup-content');
        popupContent.style.maxHeight = '90vh';
        popupContent.style.overflowY = 'auto';
      }
    });
  }

  window.closePopup = function() {
    $('#popup').hide();
  }
});
