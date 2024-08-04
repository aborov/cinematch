// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import { initSurvey } from "survey"

// Initialize survey after Turbo navigation
document.addEventListener("turbo:load", () => {
  initSurvey();
});

// Also initialize on DOMContentLoaded for the initial page load
document.addEventListener("DOMContentLoaded", () => {
  initSurvey();
});
