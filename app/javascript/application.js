// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"
import "survey"
import jquery from "jquery"
import Rails from "@rails/ujs"
import * as bootstrap from "bootstrap"

Turbo.session.drive = false

window.jQuery = jquery
window.$ = jquery
window.bootstrap = bootstrap

Rails.start()
