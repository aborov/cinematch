document.addEventListener('turbo:load', function() {
  const passwordFields = document.querySelectorAll('input[type="password"][data-complexity]');
  passwordFields.forEach(function(passwordField) {
    const complexityRequirements = JSON.parse(passwordField.dataset.complexity);
    const feedbackElement = document.getElementById('passwordFeedback');
    const confirmationField = document.getElementById('password_confirmation');
    const confirmationFeedback = document.getElementById('passwordConfirmationHelp');

    function validatePasswordComplexity() {
      const password = passwordField.value;
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
        passwordField.classList.add('is-invalid');
      } else {
        feedbackElement.style.display = 'none';
        passwordField.classList.remove('is-invalid');
        passwordField.classList.add('is-valid');
      }
    }

    function validatePasswordMatch() {
      if (passwordField.value !== confirmationField.value) {
        confirmationFeedback.textContent = 'Passwords do not match';
        confirmationFeedback.style.color = 'red';
        confirmationField.classList.add('is-invalid');
      } else {
        confirmationFeedback.textContent = 'Passwords match';
        confirmationFeedback.style.color = 'green';
        confirmationField.classList.remove('is-invalid');
        confirmationField.classList.add('is-valid');
      }
    }

    passwordField.addEventListener('input', validatePasswordComplexity);
    passwordField.addEventListener('input', validatePasswordMatch);
    if (confirmationField) {
      confirmationField.addEventListener('input', validatePasswordMatch);
    }
  });
});
