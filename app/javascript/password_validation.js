document.addEventListener('turbo:load', function() {
  const passwordField = document.querySelector('input[type="password"][data-complexity]');
  if (passwordField) {
    const complexityRequirements = JSON.parse(passwordField.dataset.complexity);
    const feedbackElement = document.getElementById('passwordFeedback');

    passwordField.addEventListener('input', function() {
      const password = this.value;
      const errors = [];

      if (password.length < 6) {
        errors.push('Password must be at least 6 characters long');
      }

      if ((password.match(/[A-Z]/g) || []).length < complexityRequirements.upper) {
        errors.push('Must contain at least one uppercase letter');
      }

      if ((password.match(/[a-z]/g) || []).length < complexityRequirements.lower) {
        errors.push('Must contain at least one lowercase letter');
      }

      if ((password.match(/[0-9]/g) || []).length < complexityRequirements.digit) {
        errors.push('Must contain at least one number');
      }

      if ((password.match(/[^A-Za-z0-9]/g) || []).length < complexityRequirements.symbol) {
        errors.push('Must contain at least one symbol');
      }

      if (errors.length > 0) {
        feedbackElement.textContent = errors.join('. ');
        feedbackElement.style.display = 'block';
        this.classList.add('is-invalid');
      } else {
        feedbackElement.style.display = 'none';
        this.classList.remove('is-invalid');
        this.classList.add('is-valid');
      }
    });
  }
});
