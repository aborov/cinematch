// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import jquery from "jquery"
import * as bootstrap from "bootstrap"

window.jQuery = jquery
window.$ = jquery
window.bootstrap = bootstrap

// Load survey.js after Turbo navigation
document.addEventListener("turbo:load", () => {
  const surveyContainer = document.querySelector('.survey-container');
  if (surveyContainer) {
    import("./survey").then(module => {
      module.initSurvey();
    });
  }
});
