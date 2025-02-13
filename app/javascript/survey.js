document.addEventListener('DOMContentLoaded', () => {
  console.log('DOM loaded, initializing survey components');
  
  // Initialize welcome modal independently
  initializeWelcomeModal();
  
  // Initialize survey form if it exists
  initializeSurvey();
});

function initializeSurvey() {
  const surveyForm = document.getElementById('survey-form');
  if (!surveyForm) return;

  let currentQuestionIndex = 0;
  const questions = document.querySelectorAll('.question-card');
  const progressBar = document.querySelector('[data-progress]');
  const responses = new Map();

  const prevButton = document.getElementById('prev-button');
  const nextButton = document.getElementById('next-button');
  const submitButton = document.getElementById('submit-button');
  const genreSelection = document.getElementById('genre-selection');

  function showCurrentQuestion() {
    questions.forEach((question, index) => {
      question.style.display = index === currentQuestionIndex ? 'block' : 'none';
    });

    // Show/hide navigation buttons based on current question
    if (prevButton) prevButton.style.display = currentQuestionIndex === 0 ? 'none' : 'block';
    if (nextButton) nextButton.style.display = currentQuestionIndex === questions.length - 1 ? 'none' : 'block';
    if (submitButton) submitButton.style.display = currentQuestionIndex === questions.length - 1 ? 'block' : 'none';
    if (genreSelection) genreSelection.style.display = currentQuestionIndex === questions.length - 1 ? 'block' : 'none';
  }

  function moveToNextQuestion() {
    if (currentQuestionIndex < questions.length - 1) {
      currentQuestionIndex++
      showCurrentQuestion()
      updateProgress()
    }
  }

  function updateProgress() {
    const progress = ((currentQuestionIndex + 1) / questions.length) * 100
    if (progressBar) {
      progressBar.style.width = `${progress}%`
      progressBar.setAttribute('aria-valuenow', progress)
    }
  }

  function showError(message) {
    const alertDiv = document.createElement('div')
    alertDiv.className = 'alert alert-danger alert-dismissible fade show'
    alertDiv.innerHTML = `
      ${message}
      <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
    `
    document.querySelector('.card-body').insertBefore(alertDiv, document.querySelector('#survey-form'))
    setTimeout(() => alertDiv.remove(), 3000)
  }

  async function handleAnswer(event) {
    const button = event.target.closest('.response-button');
    if (!button) {
      console.log('Not a response button click');
      return;
    }
    
    console.log('Response button clicked:', button);
    const value = button.dataset.value;
    const questionCard = button.closest('.question-card');
    const questionId = questionCard.dataset.questionId;

    if (questionCard.dataset.attentionCheck === 'true') {
      if (value !== questionCard.dataset.correctAnswer) {
        showError("Incorrect attention check response. Please read the question carefully.");
        return;
      }
    }

    try {
      const response = await fetch('/surveys/save_progress', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({
          personality_responses: {
            [questionId]: value
          }
        })
      });

      if (!response.ok) throw new Error('Failed to save response');
      
      responses.set(questionId, value);
      moveToNextQuestion();
    } catch (error) {
      console.error('Error saving response:', error);
      showError("Failed to save response. Please try again.");
    }
  }

  // Event Listeners
  surveyForm.addEventListener('click', handleAnswer);

  if (prevButton) {
    prevButton.addEventListener('click', () => {
      if (currentQuestionIndex > 0) {
        currentQuestionIndex--;
        showCurrentQuestion();
        updateProgress();
      }
    });
  }

  if (nextButton) {
    nextButton.addEventListener('click', moveToNextQuestion);
  }

  showCurrentQuestion();
  updateProgress();
}

function initializeWelcomeModal() {
  const welcomeModal = document.getElementById('welcomeModal');
  if (welcomeModal) {
    console.log('Welcome modal found, initializing...');
    const modal = new bootstrap.Modal(welcomeModal);
    modal.show();
  } else {
    console.log('Welcome modal not found');
  }
} 
