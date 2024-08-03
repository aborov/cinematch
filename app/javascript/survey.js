export function initSurvey() {
  // Wait for DOM content to be fully loaded
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initSurveyWhenReady);
  } else {
    initSurveyWhenReady();
  }
}

function initSurveyWhenReady() {
  setTimeout(() => {
    const surveyContainer = document.querySelector('.survey-container');
    if (surveyContainer) {
      const totalQuestions = parseInt(surveyContainer.dataset.totalQuestions, 10);
      initializeSurvey(totalQuestions);
    }
  }, 100);  // 100ms delay
}

function initializeSurvey(totalQuestions) {
  const form = document.getElementById('survey-form');
  const personalityQuestions = document.querySelectorAll('#personality-questions .question-container');
  const genreSelection = document.getElementById('genre-selection');
  const submitButton = document.getElementById('submit-button');
  const prevButton = document.getElementById('prev-button');
  const nextButton = document.getElementById('next-button');
  const progressBar = document.getElementById('survey-progress');
  const personalityInstructions = document.getElementById('personality-instructions');
  let currentQuestion = 0;

  // Check if all necessary elements are present
  if (!form) console.error('Form is missing');
  if (!personalityQuestions.length) console.error('Personality questions are missing');
  if (!genreSelection) console.error('Genre selection is missing');
  if (!submitButton) console.error('Submit button is missing');
  if (!prevButton) console.error('Previous button is missing');
  if (!nextButton) console.error('Next button is missing');
  if (!progressBar) console.error('Progress bar is missing');
  if (!personalityInstructions) console.error('Personality instructions are missing');

  if (!form || !personalityQuestions.length || !genreSelection || !submitButton || !prevButton || !nextButton || !progressBar || !personalityInstructions) {
    console.error('Some survey elements are missing');
    return;
  }

  function updateProgress() {
    const progress = ((currentQuestion + 1) / totalQuestions) * 100;
    progressBar.style.width = `${progress}%`;
    progressBar.setAttribute('aria-valuenow', progress);
    progressBar.textContent = `${Math.round(progress)}%`;
  }

  function showQuestion(index) {
    personalityQuestions.forEach((q, i) => {
      q.style.display = i === index ? 'block' : 'none';
    });

    prevButton.style.display = index > 0 ? 'inline-block' : 'none';
    nextButton.style.display = index < personalityQuestions.length ? 'inline-block' : 'none';
    nextButton.disabled = !isQuestionAnswered(index);
    submitButton.style.display = 'none';
    personalityInstructions.style.display = 'block';

    updateProgress();
  }

  function showGenreSelection() {
    personalityQuestions.forEach(q => q.style.display = 'none');
    genreSelection.style.display = 'block';
    submitButton.style.display = 'inline-block';
    prevButton.style.display = 'inline-block';
    nextButton.style.display = 'none';
    personalityInstructions.style.display = 'none';
    updateProgress();
  }

  function isQuestionAnswered(index) {
    const currentQuestion = personalityQuestions[index];
    if (!currentQuestion) return false;
    const currentQuestionRadios = currentQuestion.querySelectorAll('input[type="radio"]');
    return Array.from(currentQuestionRadios).some(radio => radio.checked);
  }

  function showNextQuestion() {
    if (currentQuestion < personalityQuestions.length - 1) {
      currentQuestion++;
      showQuestion(currentQuestion);
    } else if (currentQuestion === personalityQuestions.length - 1) {
      currentQuestion++;
      showGenreSelection();
    }
  }

  personalityQuestions.forEach((question, index) => {
    const radioButtons = question.querySelectorAll('input[type="radio"]');
    radioButtons.forEach(radio => {
      radio.addEventListener('change', () => {
        nextButton.disabled = false;
        setTimeout(showNextQuestion, 300); // Delay to show the selection before moving to next question
      });
    });
  });

  nextButton.addEventListener('click', showNextQuestion);

  prevButton.addEventListener('click', function () {
    if (currentQuestion > 0) {
      currentQuestion--;
      if (currentQuestion < personalityQuestions.length) {
        showQuestion(currentQuestion);
      } else {
        showGenreSelection();
      }
    }
  });

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    this.submit();
  });

  showQuestion(0);

  // Show the welcome modal if it's the first time the user has signed up
  if (localStorage.getItem('showWelcomeModal') !== 'false') {
    const welcomeModal = new bootstrap.Modal(document.getElementById('welcomeModal'));
    welcomeModal.show();
    localStorage.setItem('showWelcomeModal', 'false'); // Ensure it only shows once
  }
}
