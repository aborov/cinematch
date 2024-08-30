import { Application } from "@hotwired/stimulus"
import "@hotwired/turbo-rails"
import "controllers"
import jquery from "jquery"
window.jQuery = jquery
window.$ = jquery

import * as bootstrap from "bootstrap"
window.bootstrap = bootstrap

import "recaptcha"
import "chart.js"
import "./pwa/companion"

import { Tooltip } from 'bootstrap'

const application = Application.start()

// Configure Stimulus development experience
application.debug = false
window.Stimulus = application

export { application }

document.addEventListener('DOMContentLoaded', addCSRFTokenToForms);

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
