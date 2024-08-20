document.addEventListener('turbo:load', function() {
  if (typeof grecaptcha !== 'undefined' && grecaptcha) {
    grecaptcha.reset();
  }
});
