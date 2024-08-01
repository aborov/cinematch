$(document).on('turbolinks:load', function () {
  $(document).on('click', '.show-details', function (e) {
    e.preventDefault();
    var id = $(this).data('id');
    var type = $(this).data('type');
    var matchScore = $(this).closest('.card').find('.badge').text();
    showDetails(id, type, matchScore);
  });

  window.showDetails = function (id, type, matchScore) {
    $.ajax({
      url: `/recommendations/${id}?type=${type}`,
      method: 'GET',
      dataType: 'json',
      success: function (data) {
        var country = data.production_countries.map(c => c.name === 'United States of America' ? 'USA' : c.name).join(', ');
        var details = `
          <div class="row">
            <div class="col-md-4">
              <img src="https://image.tmdb.org/t/p/w500${data.poster_path}" class="img-fluid rounded" alt="${data.title || data.name}">
            </div>
            <div class="col-md-8">
              <h2 class="text-warning d-flex justify-content-between align-items-start mb-3">
                <span>${data.title || data.name}</span>
                <span class="badge badge-large">${matchScore}</span>
              </h2>
              <p><strong>Runtime:</strong> ${data.runtime || data.episode_run_time[0]} minutes</p>
              <p><strong>Release Year:</strong> ${(data.release_date || data.first_air_date).substring(0, 4)}</p>
              <p><strong>Country:</strong> ${country}</p>
              <p><strong>TMDb Rating:</strong> ${data.vote_average}</p>
              <p><strong>Description:</strong> ${data.overview}</p>
              <p><strong>Director(s):</strong> ${data.credits.crew.filter(c => c.job === 'Director').map(d => d.name).join(', ')}</p>
              <p><strong>Cast:</strong> ${data.credits.cast.slice(0, 5).map(c => c.name).join(', ')}</p>
              ${data.videos && data.videos.results && data.videos.results.length > 0 ? 
                `<iframe width="100%" height="315" src="https://www.youtube.com/embed/${data.videos.results[0].key}" frameborder="0" allowfullscreen></iframe>` : 
                '<p>No video available</p>'}
            </div>
          </div>
        `;
        $('#popup-details').html(details);
        $('#detailsModal').modal('show');
      }
    });
  }
});
