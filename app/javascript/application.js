import { Application } from "@hotwired/stimulus"
import jquery from "jquery"
window.jQuery = jquery
window.$ = jquery

// import * as bootstrap from "bootstrap"
// window.bootstrap = bootstrap

import "recaptcha"
import "chart.js"
import "./pwa/companion"

import { Tooltip } from 'bootstrap'

const application = Application.start()
application.debug = false
window.Stimulus = application

document.addEventListener('DOMContentLoaded', () => {
  addCSRFTokenToForms();
  initializeWatchlistControllers();
});

function addCSRFTokenToForms() {
  var token = document.querySelector('meta[name="csrf-token"]').getAttribute('content');
  document.querySelectorAll('form').forEach(function(form) {
    var input = document.createElement('input');
    input.type = 'hidden';
    input.name = 'authenticity_token';
    input.value = token;
    form.appendChild(input);
  });
}

function initializeWatchlistControllers() {
  const watchlistToggles = document.querySelectorAll('[data-controller="watchlist"]');
  watchlistToggles.forEach(toggle => {
    window.Stimulus.load(toggle);
  });
}

export { application }

document.addEventListener('DOMContentLoaded', function() {
  $(document).ajaxError(function(event, xhr, settings) {
    if (xhr.status === 401) {
      window.location.href = '/users/sign_in';
    }
  });

  $(document).ajaxSuccess(function(event, xhr, settings) {
    if (xhr.responseJSON && xhr.responseJSON.redirect) {
      window.location.href = xhr.responseJSON.redirect;
    }
  });
});

//= require chartkick
//= require Chart.bundle
