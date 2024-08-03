// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import jquery from "jquery"
import * as bootstrap from "bootstrap"
import { initSurvey } from "survey"

window.jQuery = jquery
window.$ = jquery
window.bootstrap = bootstrap

// Initialize survey after Turbo navigation
document.addEventListener("turbo:load", () => {
  initSurvey();
});
