const RESPONSE_VALUES = {
  'Strongly_Disagree': 1,
  'Disagree': 2,
  'Neutral': 3,
  'Agree': 4,
  'Strongly_Agree': 5
};

document.addEventListener('DOMContentLoaded', () => {
  console.log('DOM loaded, initializing survey components');
  
  // Initialize welcome modal independently
  initializeWelcomeModal();
  
  // Initialize survey form if it exists
  initializeSurvey();
});

function initializeSurvey() {
  const surveyForm = document.getElementById('survey-form');
  if (!surveyForm) {
    console.log('Survey form not found');
    return;
  }
  console.log('Survey form found, initializing...');

  let currentQuestionIndex = 0;
  const questions = document.querySelectorAll('.question-card');
  console.log(`Found ${questions.length} questions`);
  
  // Validate attention check questions
  validateAttentionCheckQuestions(questions);
  
  const progressBar = document.querySelector('[data-progress]');
  const responses = new Map();

  const prevButton = document.getElementById('prev-button');
  const nextButton = document.getElementById('next-button');
  const submitButton = document.getElementById('submit-button');
  const genreSelection = document.getElementById('genre-selection');
  
  console.log('Navigation buttons:', { 
    prevButton: !!prevButton, 
    nextButton: !!nextButton, 
    submitButton: !!submitButton 
  });

  function validateAttentionCheckQuestions(questions) {
    questions.forEach((question, index) => {
      // Clean up the attribute value by removing any extra quotes
      const attentionCheckAttr = question.dataset.attentionCheck;
      const isAttentionCheck = attentionCheckAttr === 'true' || attentionCheckAttr === '"true"';
      const questionId = question.dataset.questionId;
      
      if (isAttentionCheck) {
        // Clean up the correct answer by removing any extra quotes
        let correctAnswer = question.dataset.correctAnswer;
        if (correctAnswer && correctAnswer.startsWith('"') && correctAnswer.endsWith('"')) {
          correctAnswer = correctAnswer.substring(1, correctAnswer.length - 1);
          // Update the dataset with the cleaned value
          question.dataset.correctAnswer = correctAnswer;
        }
        
        console.log(`Attention check found at index ${index}:`, {
          questionId,
          correctAnswer,
          hasCorrectAnswer: !!correctAnswer,
          correctValue: RESPONSE_VALUES[correctAnswer]
        });
        
        if (!correctAnswer) {
          console.error(`Attention check question ${questionId} is missing correct_answer attribute!`);
        }
        
        // Ensure the attention-check attribute is properly set
        question.dataset.attentionCheck = 'true';
      }
    });
  }

  function showCurrentQuestion() {
    console.log('Showing question at index:', currentQuestionIndex);
    
    // Hide all questions
    questions.forEach(q => q.style.display = 'none');
    
    // Show genre selection if we're at the end
    if (genreSelection && currentQuestionIndex === questions.length) {
      console.log('Showing genre selection');
      genreSelection.style.display = 'block';
      
      // Update navigation buttons
      if (prevButton) prevButton.style.display = 'inline-block';
      if (nextButton) nextButton.style.display = 'none';
      
      // Show the complete button instead of the next button
      const completeButton = document.getElementById('complete-survey');
      if (completeButton) completeButton.style.display = 'inline-block';
      
      return;
    }
    
    // If we've reached the end of the survey and there's no genre selection (extended survey)
    if (currentQuestionIndex >= questions.length && !genreSelection) {
      console.log('End of extended survey reached, showing complete button');
      
      // Hide all questions
      questions.forEach(q => q.style.display = 'none');
      
      // Show a message indicating the survey is complete
      const surveyContainer = document.querySelector('.survey-container');
      if (surveyContainer) {
        // Create or show the completion message
        let completionMessage = document.getElementById('survey-completion-message');
        if (!completionMessage) {
          completionMessage = document.createElement('div');
          completionMessage.id = 'survey-completion-message';
          completionMessage.className = 'text-center p-4';
          completionMessage.innerHTML = `
            <div class="mb-4">
              <i class="fas fa-check-circle text-success fa-3x"></i>
              <h3 class="mt-3" style="color: var(--jonquil);">You've completed all the questions!</h3>
              <p class="mb-4">Click the "Complete Survey" button below to submit your responses and view your results.</p>
            </div>
          `;
          surveyContainer.appendChild(completionMessage);
        }
        completionMessage.style.display = 'block';
      }
      
      // Update navigation buttons
      if (prevButton) prevButton.style.display = 'inline-block';
      if (nextButton) nextButton.style.display = 'none';
      
      // Show the complete button
      const completeButton = document.getElementById('complete-survey');
      if (completeButton) completeButton.style.display = 'inline-block';
      
      return;
    }
    
    // Show current question
    if (currentQuestionIndex < questions.length) {
      const currentQuestion = questions[currentQuestionIndex];
      currentQuestion.style.display = 'block';
      
      console.log('Current question check:', {
        index: currentQuestionIndex,
        id: currentQuestion.dataset.questionId,
        isAttentionCheck: currentQuestion.dataset.attentionCheck === 'true',
        attentionCheckAttr: currentQuestion.dataset.attentionCheck
      });
      
      // Clean up the attribute value by removing any extra quotes
      const attentionCheckAttr = currentQuestion.dataset.attentionCheck;
      const isAttentionCheck = attentionCheckAttr === 'true' || attentionCheckAttr === '"true"';
      
      // Update navigation buttons
      if (prevButton) {
        prevButton.style.display = currentQuestionIndex > 0 ? 'inline-block' : 'none';
      }
      
      if (nextButton) {
        // For attention checks, hide Next button until correct answer is selected
        if (isAttentionCheck) {
          console.log('Current question is an attention check, hiding Next button');
          nextButton.style.display = 'none';
        } else {
          console.log('Current question is not an attention check, showing Next button');
          nextButton.style.display = 'inline-block';
        }
      }
      
      if (submitButton) {
        submitButton.style.display = 'none';
      }
    }
  }

  function moveToNextQuestion() {
    console.log('Moving to next question, current index:', currentQuestionIndex);
    
    if (currentQuestionIndex < questions.length - 1) {
      currentQuestionIndex++;
      console.log('New question index:', currentQuestionIndex);
      showCurrentQuestion();
      updateProgress();
    } else if (genreSelection && currentQuestionIndex === questions.length - 1) {
      console.log('Moving to genre selection');
      currentQuestionIndex++;
      showCurrentQuestion();
      updateProgress();
    } else {
      console.log('Reached end of survey');
      currentQuestionIndex = questions.length; // Ensure we're at the end
      showCurrentQuestion(); // This will now show the completion message for extended surveys
      updateProgress();
    }
  }

  function updateProgress() {
    const isBasicSurvey = document.querySelector('[data-survey-type="basic"]') !== null;
    const totalSteps = isBasicSurvey ? questions.length + 1 : questions.length;
    const currentStep = Math.min(currentQuestionIndex + 1, totalSteps);
    const progress = (currentStep / totalSteps) * 100;
    
    console.log(`Updating progress: ${progress}%`);
    if (progressBar) {
      progressBar.style.width = `${progress}%`;
      progressBar.setAttribute('aria-valuenow', progress);
    }
  }

  function showError(message) {
    console.error('Error:', message);
    const alertDiv = document.createElement('div');
    alertDiv.className = 'alert alert-danger alert-dismissible fade show';
    alertDiv.innerHTML = `
      ${message}
      <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
    `;
    document.querySelector('.card-body').insertBefore(alertDiv, document.querySelector('#survey-form'));
    setTimeout(() => alertDiv.remove(), 3000);
  }

  function debugResponses(label) {
    console.log(`--- Responses Map (${label}) ---`);
    console.log(`Total responses: ${responses.size}`);
    responses.forEach((value, key) => {
      console.log(`Question ID: ${key}, Response: ${value}`);
    });
    console.log('------------------------');
  }

  async function handleAnswer(event) {
    const button = event.target.closest('.response-button');
    if (!button) {
      console.log('Not a response button click');
      return;
    }
    
    console.log('Response button clicked:', button);
    debugResponses('Before handling response');
    
    const stringValue = button.dataset.value;
    const value = RESPONSE_VALUES[stringValue];
    const questionCard = button.closest('.question-card');
    const questionId = questionCard.dataset.questionId;
    
    console.log('Processing response:', {
      questionId,
      stringValue,
      numericValue: value,
      questionCardData: {
        ...questionCard.dataset
      }
    });
    
    // Clean up the attribute value by removing any extra quotes
    const attentionCheckAttr = questionCard.dataset.attentionCheck;
    const isAttentionCheck = attentionCheckAttr === 'true' || attentionCheckAttr === '"true"';
    
    // Debug attention check attributes
    console.log('Question card attributes:', {
      id: questionId,
      isAttentionCheck,
      attentionCheckAttr,
      correctAnswer: questionCard.dataset.correctAnswer,
      correctValue: questionCard.dataset.correctAnswer ? RESPONSE_VALUES[questionCard.dataset.correctAnswer] : null,
      selectedValue: value
    });

    // Handle attention check questions
    if (isAttentionCheck) {
      console.log('Handling attention check question');
      // Clean up the correct answer by removing any extra quotes
      let correctAnswer = questionCard.dataset.correctAnswer;
      if (correctAnswer && correctAnswer.startsWith('"') && correctAnswer.endsWith('"')) {
        correctAnswer = correctAnswer.substring(1, correctAnswer.length - 1);
      }
      
      const correctValue = RESPONSE_VALUES[correctAnswer];
      const attentionNotice = questionCard.querySelector('.attention-check-notice');
      
      console.log('Attention check validation:', {
        questionId,
        correctAnswer,
        correctValue,
        selectedValue: value,
        isCorrect: value === correctValue
      });
      
      if (value !== correctValue) {
        console.log('Incorrect attention check response');
        if (attentionNotice) {
          attentionNotice.style.display = 'block';
          attentionNotice.classList.add('alert', 'alert-danger');
          attentionNotice.innerHTML = '<i class="fas fa-exclamation-circle"></i> Incorrect attention check response. Please read the question carefully and select the correct answer to proceed.';
        }
        
        // Remove any previous highlighting
        questionCard.querySelectorAll('.response-button').forEach(btn => {
          btn.classList.remove('active', 'btn-primary');
          btn.classList.add('btn-outline-primary');
        });
        
        // Clear any previous response for this question
        responses.delete(questionId);
        console.log('Cleared response for attention check question');
        
        return; // Return early on incorrect attention check
      } else {
        console.log('Correct attention check response');
        // Hide the attention notice if answer is correct
        if (attentionNotice) {
          attentionNotice.style.display = 'none';
        }
        
        // Track the correct attention check response in memory only, don't save to database
        highlightSelectedButton(button);
        
        // Set the response in our tracking map
        responses.set(questionId, value);
        debugResponses('After setting attention check response');
        
        // Automatically move to next question for correct attention check
        setTimeout(() => moveToNextQuestion(), 500);
        
        return; // Return early after handling correct attention check
      }
    }

    try {
      console.log(`Saving response for question ${questionId}: ${value}`);
      
      const requestBody = {
        survey_response: {
          question_id: questionId,
          response: String(value)
        }
      };
      
      console.log('Request body:', JSON.stringify(requestBody));
      
      const response = await fetch('/surveys/save_progress', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify(requestBody)
      });

      const responseData = await response.json();
      console.log('Response from server:', responseData);

      if (!response.ok) {
        console.error('Server returned error status:', response.status);
        throw new Error('Failed to save response');
      }
      
      highlightSelectedButton(button);
      responses.set(questionId, value);
      console.log(`Response for question ${questionId} set to ${value}`);
      debugResponses('After setting regular response');
      
      // Check if all personality questions are answered before showing genre selection
      const isBasicSurvey = document.querySelector('[data-survey-type="basic"]') !== null;
      const allQuestionsAnswered = Array.from(questions).every(q => 
        responses.has(q.dataset.questionId) || q.dataset.attentionCheck === 'true'
      );
      
      console.log('Navigation check:', {
        isBasicSurvey,
        allQuestionsAnswered,
        currentQuestionIndex,
        totalQuestions: questions.length
      });
      
      if (isBasicSurvey && allQuestionsAnswered && currentQuestionIndex === questions.length - 1) {
        if (genreSelection) {
          console.log('All questions answered, moving to genre selection');
          currentQuestionIndex++;
          showCurrentQuestion();
        }
      } else {
        console.log('Moving to next question');
        moveToNextQuestion();
      }
    } catch (error) {
      console.error('Error saving response:', error);
      showError("Failed to save response. Please try again.");
    }
  }

  function highlightSelectedButton(button) {
    const questionCard = button.closest('.question-card');
    questionCard.querySelectorAll('.response-button').forEach(btn => {
      btn.classList.remove('active', 'btn-primary');
      btn.classList.add('btn-outline-primary');
    });
    button.classList.remove('btn-outline-primary');
    button.classList.add('active', 'btn-primary');
  }

  // Function to check if current question is an attention check and if it's answered correctly
  function isAttentionCheckAnsweredCorrectly() {
    if (currentQuestionIndex >= questions.length) return true;
    
    const currentQuestion = questions[currentQuestionIndex];
    
    // Clean up the attribute value by removing any extra quotes
    const attentionCheckAttr = currentQuestion.dataset.attentionCheck;
    const isAttentionCheck = attentionCheckAttr === 'true' || attentionCheckAttr === '"true"';
    
    if (!isAttentionCheck) return true;
    
    // This is an attention check question
    const questionId = currentQuestion.dataset.questionId;
    
    // Clean up the correct answer by removing any extra quotes
    let correctAnswer = currentQuestion.dataset.correctAnswer;
    if (correctAnswer && correctAnswer.startsWith('"') && correctAnswer.endsWith('"')) {
      correctAnswer = correctAnswer.substring(1, correctAnswer.length - 1);
    }
    
    const correctValue = RESPONSE_VALUES[correctAnswer];
    
    // Check if the question has been answered and if the answer is correct
    const hasResponse = responses.has(questionId);
    const responseValue = hasResponse ? responses.get(questionId) : null;
    const isCorrect = hasResponse && responseValue === correctValue;
    
    console.log('Attention check validation in isAttentionCheckAnsweredCorrectly:', {
      questionId,
      correctAnswer,
      correctValue,
      hasResponse,
      responseValue,
      isCorrect,
      allResponses: Array.from(responses.entries())
    });
    
    return isCorrect;
  }

  // Add direct click handlers to response buttons
  document.querySelectorAll('.response-button').forEach(button => {
    button.addEventListener('click', handleAnswer);
    console.log('Added click handler to response button:', button.textContent);
  });

  // Event Listeners
  if (prevButton) {
    prevButton.addEventListener('click', () => {
      console.log('Previous button clicked');
      if (currentQuestionIndex > 0) {
        currentQuestionIndex--;
        showCurrentQuestion();
        updateProgress();
      }
    });
  }

  if (nextButton) {
    nextButton.addEventListener('click', () => {
      console.log('Next button clicked');
      debugResponses('Next button click');
      
      // Check if current question is within bounds
      if (currentQuestionIndex < questions.length) {
        const currentQuestion = questions[currentQuestionIndex];
        const questionId = currentQuestion.dataset.questionId;
        
        // Clean up the attribute value by removing any extra quotes
        const attentionCheckAttr = currentQuestion.dataset.attentionCheck;
        const isAttentionCheck = attentionCheckAttr === 'true' || attentionCheckAttr === '"true"';
        
        console.log('Current question check:', {
          index: currentQuestionIndex,
          id: questionId,
          isAttentionCheck,
          attentionCheckAttr
        });
        
        // Check if the question has been answered
        if (!responses.has(questionId)) {
          showError("Please answer the current question before proceeding.");
          return;
        }
        
        // Check if current question is an attention check and if it's answered correctly
        if (isAttentionCheck && !isAttentionCheckAnsweredCorrectly()) {
          const attentionNotice = currentQuestion.querySelector('.attention-check-notice');
          
          if (attentionNotice) {
            attentionNotice.style.display = 'block';
            attentionNotice.classList.add('alert', 'alert-danger');
            attentionNotice.innerHTML = '<i class="fas fa-exclamation-circle"></i> Incorrect attention check response. Please read the question carefully and select the correct answer to proceed.';
          }
          
          return;
        }
      }
      
      moveToNextQuestion();
    });
  }

  // Add event listener for save progress button
  const saveProgressButton = document.getElementById('save-progress');
  if (saveProgressButton) {
    saveProgressButton.addEventListener('click', async () => {
      try {
        const response = await fetch('/surveys/save_progress', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
          },
          body: JSON.stringify({
            save_progress: true
          })
        });

        if (!response.ok) throw new Error('Failed to save progress');
        
        // Show the save progress modal
        const saveProgressModal = new bootstrap.Modal(document.getElementById('saveProgressModal'));
        saveProgressModal.show();
      } catch (error) {
        console.error('Error saving progress:', error);
        showError("Failed to save progress. Please try again.");
      }
    });
  }

  // Add event listener for the Complete Survey button
  const completeButton = document.querySelector('#complete-survey');
  if (completeButton) {
    completeButton.addEventListener('click', function(event) {
      event.preventDefault();
      console.log('Complete Survey button clicked');
      
      // Check if we need to collect genre preferences
      const genreCheckboxes = document.querySelectorAll('input[name="favorite_genres[]"]:checked');
      if (genreSelection && genreSelection.style.display === 'block' && genreCheckboxes.length === 0) {
        showError('Please select at least one favorite genre before completing the survey.');
        return;
      }
      
      // Submit the form
      const form = document.getElementById('survey-form');
      if (form) {
        console.log('Submitting survey form');
        
        // Create a hidden input to indicate form submission
        const hiddenInput = document.createElement('input');
        hiddenInput.type = 'hidden';
        hiddenInput.name = 'submit_survey';
        hiddenInput.value = 'true';
        form.appendChild(hiddenInput);
        
        // Add survey type if not already present
        if (!form.querySelector('input[name="type"]')) {
          const typeInput = document.createElement('input');
          typeInput.type = 'hidden';
          typeInput.name = 'type';
          typeInput.value = document.querySelector('meta[name="survey-type"]')?.content || 'basic';
          form.appendChild(typeInput);
        }
        
        // Submit the form
        form.submit();
      } else {
        console.error('Survey form not found');
        showError('An error occurred. Please refresh the page and try again.');
      }
    });
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
