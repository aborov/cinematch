import { Application } from "@hotwired/stimulus"
import "@hotwired/turbo-rails"
import "controllers"
import jquery from "jquery"
window.jQuery = jquery
window.$ = jquery

import * as bootstrap from "bootstrap"
window.bootstrap = bootstrap

const application = Application.start()

// Configure Stimulus development experience
application.debug = false
window.Stimulus = application

export { application }
