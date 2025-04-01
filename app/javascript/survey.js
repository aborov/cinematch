const RESPONSE_VALUES = {
  'Strongly_Disagree': 1,
  'Disagree': 2,
  'Neutral': 3,
  'Agree': 4,
  'Strongly_Agree': 5
};

// Add the reverse mapping
const RESPONSE_VALUE_STRINGS = Object.fromEntries(
  Object.entries(RESPONSE_VALUES).map(([key, value]) => [value, key])
);
// RESPONSE_VALUE_STRINGS will be: { '1': 'Strongly_Disagree', '2': 'Disagree', ... }

// Global variables and helper functions
let currentQuestionIndex = 0;
let progressBar, prevButton, nextButton, genreSelection, completeBtn, responses, saveProgressButton;

// Use turbo:load for Turbo Drive compatibility
document.addEventListener('turbo:load', () => {
  // Remove setTimeout wrapper
  console.log('turbo:load event fired, initializing survey components');
  
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

  // Get survey type early
  const isBasicSurvey = document.querySelector('meta[name="survey-type"]')?.getAttribute('content') === 'basic';
  console.log('Survey type:', isBasicSurvey ? 'basic' : 'extended');

  // Debug the survey container contents
  const surveyContainer = document.querySelector('.survey-container');
  if (surveyContainer) {
    console.log('Survey container HTML:', surveyContainer.innerHTML);
    console.log('Survey container children:', surveyContainer.children.length);
    
    // Check if genre selection is in the DOM but possibly not with the expected ID
    Array.from(surveyContainer.children).forEach((child, index) => {
      console.log(`Child ${index}:`, child.id, child.tagName, child.className);
      
      // Look for any element containing "genre" in it
      if (child.innerHTML.toLowerCase().includes('genre')) {
        console.log('Found element with "genre" text:', child);
      }
    });
  } else {
    console.log('Survey container not found');
  }
  
  currentQuestionIndex = 0;
  const questions = document.querySelectorAll('.question-card');
  const totalQuestions = questions.length;
  responses = new Map();
  console.log(`Found ${totalQuestions} questions`);
  
  // Set initial question counter
  const questionCounter = document.querySelector('.text-muted');
  if (questionCounter) {
    questionCounter.textContent = `Question 1 of ${totalQuestions}`;
  }
  
  // Initialize UI elements
  progressBar = document.querySelector('[data-progress]');
  prevButton = document.getElementById('prev-button');
  nextButton = document.getElementById('next-button');
  const submitButton = document.getElementById('submit-button');
  genreSelection = document.getElementById('genre-selection');
  completeBtn = document.getElementById('complete-survey');
  saveProgressButton = document.getElementById('save-progress');
  
  // New Debugging Log
  const initialModalCheck = document.getElementById('saveProgressModal');
  console.log('Modal element check during initializeSurvey:', initialModalCheck);
  // End New Debugging Log
  
  // Initialize the save progress button for extended survey
  if (saveProgressButton) {
    if (!isBasicSurvey) {
      saveProgressButton.style.display = 'block';
      console.log('Save Progress button displayed for extended survey');
    } else {
      saveProgressButton.style.display = 'none';
      console.log('Save Progress button hidden for basic survey');
    }
  }
  
  // Verify that complete button exists and has the proper event handler
  ensureCompleteButtonFunctionality();
  
  // Load saved responses if any
  let hasResumableProgress = false;
  questions.forEach(questionCard => {
    const questionId = questionCard.dataset.questionId;
    const savedResponseNumeric = questionCard.dataset.savedResponse; // e.g., "3"

    if (savedResponseNumeric) {
      // Find the string representation (e.g., "Neutral") from the numeric value
      const savedResponseString = RESPONSE_VALUE_STRINGS[savedResponseNumeric];

      if (savedResponseString) {
        // Store the numeric response in the map (consistent with how answers are saved)
        // Store as string to match button values during handling
        responses.set(questionId, savedResponseString); 
        console.log(`Processing saved response: questionId=${questionId}, numeric=${savedResponseNumeric}, string=${savedResponseString}`);

        // Find and highlight the button using the string value
        const button = questionCard.querySelector(`.response-button[data-value="${savedResponseString}"]`);
        if (button) {
          markQuestionAsAnswered(questionCard, button);
          hasResumableProgress = true;
        } else {
           console.log(`Could not find button for saved response string: questionId=${questionId}, savedResponseString=${savedResponseString}`);
        }
      } else {
        console.warn(`Could not find string representation for saved response: questionId=${questionId}, numeric=${savedResponseNumeric}`);
      }
    }
  });
  
  // If there are saved responses, initialize to the next unanswered question
  if (hasResumableProgress) {
    console.log('Resumable progress detected, initializing with saved responses.'); // Added log
    initializeWithSavedResponses();
  } else {
    // Validate attention check questions
    validateAttentionCheckQuestions(questions);
    showCurrentQuestion();
    updateProgress();
  }
  
  // Check if we have the genre selection for basic survey
  console.log('Survey initialization:', { 
    isBasicSurvey,
    hasGenreSelection: !!genreSelection,
    hasCompleteButton: !!completeBtn,
    prevButton: !!prevButton, 
    nextButton: !!nextButton, 
    submitButton: !!submitButton,
    saveProgressButton: !!saveProgressButton
  });

  // Check if the question container has total_questions attribute
  const questionContainer = document.querySelector('.question-container');
  if (questionContainer) {
    const totalQuestionsFromData = parseInt(questionContainer.dataset.totalQuestions, 10);
    console.log('Question container found:', {
      totalQuestionsFromData,
      totalQuestions
    });
  } else {
    console.error('Question container not found!');
  }
  
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
    
    // Log a summary of all attention check questions
    const attentionChecks = Array.from(questions).filter(q => q.dataset.attentionCheck === 'true');
    console.log(`Found ${attentionChecks.length} attention check questions:`);
    attentionChecks.forEach(q => console.log(`- Question ID: ${q.dataset.questionId}, Correct Answer: ${q.dataset.correctAnswer}`));
  }

  function showCurrentQuestion() {
    const questionContainer = document.querySelector('.question-container');
    if (!questionContainer) {
      console.error('Question container not found in showCurrentQuestion');
      return;
    }
    
    const totalQuestionsFromData = parseInt(questionContainer.dataset.totalQuestions, 10);
    const isBasicSurvey = document.querySelector('meta[name="survey-type"]')?.getAttribute('content') === 'basic';
    // Remove redundant DOM queries, use global variables assigned in initializeSurvey
    // genreSelection = document.getElementById('genre-selection');
    // completeBtn = document.getElementById('complete-survey');
    // nextButton = document.getElementById('next-button');
    // prevButton = document.getElementById('prev-button');
    // saveProgressButton = document.getElementById('save-progress');
    const atGenreSelection = isBasicSurvey && currentQuestionIndex >= totalQuestionsFromData;
    const isLastQuestion = currentQuestionIndex === totalQuestionsFromData - 1;

    // Enhanced debugging for button elements
    console.log('Button Elements:', {
      completeBtn: completeBtn ? {
        id: completeBtn.id,
        display: completeBtn.style.display,
        className: completeBtn.className
      } : 'Not found',
      nextButton: nextButton ? {
        id: nextButton.id,
        display: nextButton.style.display,
        className: nextButton.className
      } : 'Not found',
      prevButton: prevButton ? {
        id: prevButton.id,
        display: prevButton.style.display,
        className: prevButton.className
      } : 'Not found'
    });

    // If we need to show genre selection but it doesn't exist, create it
    if (isBasicSurvey && !genreSelection) {
      console.log('Creating genre selection element');
      createGenreSelectionElement();
      genreSelection = document.getElementById('genre-selection');
    }

    console.log('showCurrentQuestion debug:', {
      currentQuestionIndex,
      totalQuestionsFromData,
      isBasicSurvey,
      atGenreSelection,
      isLastQuestion,
      hasGenreSelection: !!genreSelection,
      genreSelectionDisplay: genreSelection ? genreSelection.style.display : 'N/A',
      completeButtonExists: !!completeBtn,
      nextButtonExists: !!nextButton,
      prevButtonExists: !!prevButton,
      saveProgressButtonExists: !!saveProgressButton
    });

    // Get navigation container
    const navContainer = document.querySelector('.navigation-buttons');
    if (!navContainer) {
      console.error('Navigation container not found in showCurrentQuestion');
      return;
    }

    // For genre selection
    if (atGenreSelection && isBasicSurvey) {
      console.log('Showing genre selection');
      
      // Hide all questions
      document.querySelectorAll('.question-card').forEach(card => {
        card.style.display = 'none';
      });
      
      // Show genre selection
      if (genreSelection) {
        genreSelection.style.display = 'block';
        console.log('Genre selection displayed');
      }
      
      // Hide question counter
      const questionCounter = document.querySelector('.text-muted');
      if (questionCounter) {
        questionCounter.style.display = 'none';
      }
      
      // Set up navigation buttons for genre selection
      if (prevButton) prevButton.style.display = 'block';
      if (nextButton) nextButton.style.display = 'none';
      if (completeBtn) {
        completeBtn.style.display = 'block';
        completeBtn.innerHTML = 'Complete Survey<i class="fas fa-check ms-2"></i>';
        console.log('Complete button displayed for genre selection in showCurrentQuestion');
      } else {
        // This error should ideally not happen now as the button exists in HTML
        console.error('Complete button reference not found in showCurrentQuestion!');
      }
      if (saveProgressButton) {
        saveProgressButton.style.display = 'none';
      }
      
      // Ensure the navigation container is visible
      navContainer.style.display = 'flex';
      console.log('Navigation container displayed in showCurrentQuestion');
      
      return; // Return after handling genre selection display
    } else { // Regular question handling (non-genre selection)
      // Hide all questions first
      document.querySelectorAll('.question-card').forEach(card => {
        card.style.display = 'none';
      });

      // Hide genre selection by default (will show it if needed)
      if (genreSelection) {
        genreSelection.style.display = 'none';
      }

      // Specifically check for the Save Progress button existence
      if (!saveProgressButton && !isBasicSurvey) {
        console.error('Save Progress button not found for extended survey');
        // Try to find it with a broader selector just in case
        const possibleSaveBtn = document.querySelector('.save-progress-button');
        if (possibleSaveBtn) {
          console.log('Found Save Progress button with class selector');
          saveProgressButton = possibleSaveBtn;
        }
      }

      // Always display the save progress button for extended survey
      if (saveProgressButton) {
        if (!isBasicSurvey) {
          saveProgressButton.style.display = 'block';
          console.log('Save Progress button shown for extended survey');
        } else {
          saveProgressButton.style.display = 'none';
          console.log('Save Progress button hidden for basic survey');
        }
      }

      // Show current question
      const currentQuestion = document.querySelector(`.question-card[data-question-index="${currentQuestionIndex}"]`);
      if (currentQuestion) {
        currentQuestion.style.display = 'block';
        
        // Update navigation buttons
        if (prevButton) {
          prevButton.style.display = currentQuestionIndex > 0 ? 'block' : 'none';
        }
        
        // For basic survey, on last question show both Next and Complete buttons
        if (isBasicSurvey && isLastQuestion) {
          // On last question of basic survey, show Next (to genre selection) 
          if (nextButton) {
            nextButton.style.display = 'block';
            console.log('Next button shown on last question of basic survey');
          }
          
          // Hide complete button on last question (will show on genre selection)
          if (completeBtn) {
            completeBtn.style.display = 'none';
            console.log('Complete button hidden on last question of basic survey');
          }
        } 
        // For extended survey, on last question show Complete button instead of Next
        else if (!isBasicSurvey && isLastQuestion) {
          if (completeBtn) {
            completeBtn.style.display = 'block';
            completeBtn.innerHTML = 'Complete Survey<i class="fas fa-check ms-2"></i>';
            console.log('Complete button shown for last question of extended survey');
          }
          
          if (nextButton) {
            nextButton.style.display = 'none';
            console.log('Next button hidden for last question of extended survey');
          }
        }
        // For all other cases (not last question)
        else {
          if (completeBtn) {
            completeBtn.style.display = 'none';
          }
          
          if (nextButton) {
            nextButton.style.display = 'block';
            console.log('Next button shown for non-last question');
          }
        }
        
        // Ensure proper button order in the DOM
        const navButtonsContainer = document.querySelector('.navigation-buttons');
        if (navButtonsContainer) {
          // Build the desired order array, always including all buttons
          const orderedButtons = [];
          if (prevButton) orderedButtons.push(prevButton);
          if (saveProgressButton) orderedButtons.push(saveProgressButton);
          if (nextButton) orderedButtons.push(nextButton);
          if (completeBtn) orderedButtons.push(completeBtn);
          
          // Check if reordering is needed (different elements or different order)
          const currentButtons = Array.from(navButtonsContainer.children);
          let needsReorder = orderedButtons.length !== currentButtons.length;
          if (!needsReorder) {
            for (let i = 0; i < orderedButtons.length; i++) {
              if (orderedButtons[i] !== currentButtons[i]) {
                needsReorder = true;
                break;
              }
            }
          }

          // If reordering is needed, append buttons in the correct order
          if (needsReorder) {
            console.log('Reordering navigation buttons in DOM');
            orderedButtons.forEach(button => {
              // AppendChild moves the element if it's already in the DOM
              navButtonsContainer.appendChild(button); 
            });
          }
        } else {
          console.error('Navigation buttons container not found');
        }
        
        // Show question counter
        const questionCounter = document.querySelector('.text-muted');
        if (questionCounter) {
          questionCounter.style.display = 'block';
          questionCounter.textContent = `Question ${currentQuestionIndex + 1} of ${totalQuestionsFromData}`;
        }
      }
    }
  }

  function moveToNextQuestion() {
    const questionContainer = document.querySelector('.question-container');
    if (!questionContainer) {
      console.error('Question container not found in moveToNextQuestion');
      return;
    }
    
    const totalQuestionsFromData = parseInt(questionContainer.dataset.totalQuestions, 10);
    const isBasicSurvey = document.querySelector('meta[name="survey-type"]')?.getAttribute('content') === 'basic';
    const isCurrentlyLastQuestion = currentQuestionIndex === totalQuestionsFromData - 1; 
    const shouldShowGenreSelection = isBasicSurvey && isCurrentlyLastQuestion; 
    
    console.log('moveToNextQuestion debug:', {
      currentQuestionIndex,
      totalQuestionsFromData,
      isBasicSurvey,
      isCurrentlyLastQuestion,
      shouldShowGenreSelection
    });
    
    // For basic survey, check if we should move to genre selection
    if (shouldShowGenreSelection && isBasicSurvey) {
      console.log('Moving to genre selection');
      currentQuestionIndex = totalQuestionsFromData; // This will trigger genre selection display
      
      // Check if genre selection element exists
      genreSelection = document.getElementById('genre-selection');
      console.log('Genre selection element:', !!genreSelection);
      
      // If the genre selection element doesn't exist, create it
      if (!genreSelection) {
        console.log('Creating genre selection element');
        createGenreSelectionElement();
        genreSelection = document.getElementById('genre-selection');
      }
      
      // Hide all questions
      document.querySelectorAll('.question-card').forEach(card => {
        card.style.display = 'none';
      });
      
      // Show genre selection
      if (genreSelection) {
        genreSelection.style.display = 'block';
        console.log('Genre selection element displayed');
        
        // Get navigation buttons container
        const navContainer = document.querySelector('.navigation-buttons');
        if (!navContainer) {
          console.error('Navigation container not found!');
          return;
        }
        
        // Get navigation buttons
        prevButton = document.getElementById('prev-button');
        nextButton = document.getElementById('next-button');
        completeBtn = document.getElementById('complete-survey');
        
        // Create complete button if it doesn't exist
        if (!completeBtn) {
          console.log('Complete button not found, creating it');
          completeBtn = document.createElement('button');
          completeBtn.type = 'button';
          completeBtn.id = 'complete-survey';
          completeBtn.className = 'btn nav-button complete-button';
          completeBtn.innerHTML = 'Complete Survey<i class="fas fa-check ms-2"></i>';
          completeBtn.dataset.retake = document.querySelector('meta[name="retake"]')?.getAttribute('content') || 'false';
          
          // Add to navigation container
          navContainer.appendChild(completeBtn);
          console.log('Created complete button and added to navigation container');
        }
        
        // Set up buttons for genre selection
        if (prevButton) prevButton.style.display = 'block';
        if (nextButton) nextButton.style.display = 'none';
        if (completeBtn) {
          completeBtn.style.display = 'block';
          completeBtn.innerHTML = 'Complete Survey<i class="fas fa-check ms-2"></i>';
          console.log('Complete button displayed for genre selection');
        } else {
          console.error('Complete button still not found after creation attempt!');
        }
        
        // Ensure the original navigation container remains visible
        navContainer.style.display = 'flex';
        console.log('Navigation container displayed for genre selection');
        
        // Update prev button click handler specifically for genre selection
        if (prevButton) {
          // Remove existing listeners by cloning the button
          const newPrevBtn = prevButton.cloneNode(true);
          prevButton.parentNode.replaceChild(newPrevBtn, prevButton);
          prevButton = newPrevBtn;
          
          // Add new event listener for genre selection
          prevButton.addEventListener('click', () => {
            // Go back to last question from genre selection
            currentQuestionIndex = totalQuestionsFromData - 1;
            console.log('Going back from genre selection to last question');
            showCurrentQuestion();
            updateProgress();
          });
        }
        
        // Update complete button click handler if it exists
        if (completeBtn) {
          // Remove existing listeners by cloning
          const newCompleteBtn = completeBtn.cloneNode(true);
          if (completeBtn.parentNode) {
            completeBtn.parentNode.replaceChild(newCompleteBtn, completeBtn);
            completeBtn = newCompleteBtn;
          } else {
            console.warn('Cannot replace Complete button - no parent node found');
            completeBtn = newCompleteBtn;
          }
          
          completeBtn.addEventListener('click', async function(event) {
            event.preventDefault();
            console.log('Complete button clicked from genre selection');
            
            const genreCheckboxes = genreSelection.querySelectorAll('input[name="favorite_genres[]"]:checked');
            console.log('Selected genres:', Array.from(genreCheckboxes).map(cb => cb.value));
            
            if (genreCheckboxes.length === 0) {
              showError('Please select at least one favorite genre before completing the survey.');
              return;
            }
            
            // Get retake status from meta tag
            const isRetake = document.querySelector('meta[name="retake"]')?.getAttribute('content') === 'true';
            console.log('Retaking survey:', isRetake);
            
            // Collect selected genres
            const selectedGenres = [];
            genreCheckboxes.forEach(checkbox => {
              selectedGenres.push(checkbox.value);
            });
            
            // Convert responses Map to an array of objects for API submission
            const responsesArray = [];
            responses.forEach((value, key) => {
              // Convert text values to integers for submission
              let numericValue = value;
              if (typeof value === 'string') {
                const valueMap = {
                  'Strongly_Disagree': 1,
                  'Disagree': 2,
                  'Neutral': 3,
                  'Agree': 4,
                  'Strongly_Agree': 5
                };
                numericValue = valueMap[value] || value;
              }
              
              responsesArray.push({
                question_id: key,
                response: numericValue
              });
            });
            
            try {
              // Show a loading indicator
              const loadingIndicator = document.createElement('div');
              loadingIndicator.className = 'position-fixed top-0 start-0 w-100 h-100 d-flex justify-content-center align-items-center';
              loadingIndicator.style.backgroundColor = 'rgba(0, 0, 0, 0.5)';
              loadingIndicator.style.zIndex = '9999';
              loadingIndicator.innerHTML = `
                <div class="spinner-border text-light" role="status">
                  <span class="visually-hidden">Loading...</span>
                </div>
              `;
              document.body.appendChild(loadingIndicator);
              
              // Log data being sent
              console.log('Sending survey data from moveToNextQuestion:', {
                survey_responses: responsesArray,
                favorite_genres: selectedGenres,
                submit_survey: 'true',
                type: 'basic',
                retake: isRetake
              });
              
              const token = document.querySelector('meta[name="csrf-token"]').content;
              const saveResult = await fetch('/surveys', {
                method: 'POST',
                headers: {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                  'X-CSRF-Token': token
                },
                body: JSON.stringify({
                  survey_responses: responsesArray,
                  favorite_genres: selectedGenres,
                  submit_survey: 'true',
                  type: 'basic',
                  retake: isRetake
                })
              });

              // Remove loading indicator
              document.body.removeChild(loadingIndicator);

              if (!saveResult.ok) {
                const errorText = await saveResult.text();
                console.error('Error response:', errorText);
                throw new Error(`Failed to save responses: ${saveResult.status} ${errorText}`);
              }
              
              console.log('Survey saved successfully');
              
              try {
                // First check if the response is likely to be JSON based on content-type
                const contentType = saveResult.headers.get('content-type');
                let responseData = null;
                let redirectUrl = null;
                if (contentType && contentType.includes('application/json')) {
                  // Try to parse the response as JSON
                  responseData = await saveResult.json();
                  console.log('Server response:', responseData);
                  redirectUrl = responseData.redirect_url;
                } else {
                  console.warn('Response is not JSON, checking Location header', contentType);
                  const locationHeader = saveResult.headers.get('location');
                  if (locationHeader) { redirectUrl = locationHeader; }
                }

                // Handle extended vs basic survey completion flow
                if (!isBasicSurvey) {
                  // === MODIFIED: Redirect immediately for extended survey ===
                  const targetUrl = redirectUrl || '/survey_results?type=extended'; // Use redirectUrl if available
                  console.log(`Extended survey complete, redirecting to ${targetUrl}`);
                  window.location.href = targetUrl;
                } else {
                  // Basic Survey: Redirect immediately if URL is available
                  const targetUrl = redirectUrl || '/survey_results?type=basic'; // Use redirectUrl if available
                  console.log(`Basic survey complete, redirecting to ${targetUrl}`);
                  window.location.href = targetUrl;
                }
                
              } catch (jsonError) {
                console.warn('Post-processing/JSON parsing error, proceeding with fallback redirect', jsonError);
                window.location.href = isBasicSurvey ? '/survey_results?type=basic' : '/survey_results?type=extended';
              }

            } catch (error) {
              console.error('Error completing survey:', error);
              showError('Failed to complete the survey. Please try again.');
            }
          });
        }
      }
      
      // Update question counter to not show for genre selection
      const questionCounter = document.querySelector('.text-muted');
      if (questionCounter) {
        questionCounter.style.display = 'none';
        console.log('Question counter hidden for genre selection');
      }
      
      updateProgress();
      return;
    }
    
    // For all other cases
    if (currentQuestionIndex < totalQuestionsFromData - 1) {
      currentQuestionIndex++;
      showCurrentQuestion();
      updateProgress();
    } else if (currentQuestionIndex === totalQuestionsFromData - 1) {
      // At last question, just update UI to ensure buttons are correct
      showCurrentQuestion();
      updateProgress();
    }
  }

  function updateProgress() {
    const isBasicSurvey = document.querySelector('meta[name="survey-type"]')?.getAttribute('content') === 'basic';
    const questionContainer = document.querySelector('.question-container');
    if (!questionContainer) return;
    
    const questions = document.querySelectorAll('.question-card');
    const totalQuestionsFromData = questionContainer ? parseInt(questionContainer.dataset.totalQuestions, 10) : questions.length;
    
    // Count answered questions for progress calculation
    let answeredQuestions = 0;
    questions.forEach(question => {
      if (question.classList.contains('answered')) {
        answeredQuestions++;
      }
    });
    
    // Calculate progress based on answered questions and survey type
    const totalSteps = isBasicSurvey ? totalQuestionsFromData + 1 : totalQuestionsFromData; // +1 for genre selection in basic survey
    const currentStep = Math.min(currentQuestionIndex + 1, totalSteps);
    
    // Calculate progress based on answered questions
    let progress = (answeredQuestions / totalQuestionsFromData) * 100;
    
    console.log(`Updating progress: ${progress}% (${answeredQuestions} answered of ${totalQuestionsFromData})`);
    if (progressBar) {
      progressBar.style.width = `${progress}%`;
      progressBar.setAttribute('aria-valuenow', progress);
    }
    
    // Update question counter
    const questionCounter = document.querySelector('.text-muted');
    if (questionCounter && currentQuestionIndex < questions.length) {
      questionCounter.textContent = `Question ${currentQuestionIndex + 1} of ${totalQuestionsFromData}`;
      console.log(`Updating question counter: ${currentQuestionIndex + 1} of ${totalQuestionsFromData}`);
    }
  }

  function showAttentionCheckWarning(questionCard) {
    const warningElement = questionCard.querySelector('.attention-check-notice');
    if (warningElement) {
      warningElement.style.display = 'block';
      warningElement.classList.add('animate__animated', 'animate__shakeX');
      setTimeout(() => {
        warningElement.classList.remove('animate__shakeX');
      }, 1000);
    }
  }

  function showError(message) {
    let errorContainer = document.getElementById('error-container');
    
    // Create error container if it doesn't exist
    if (!errorContainer) {
      errorContainer = document.createElement('div');
      errorContainer.id = 'error-container';
      errorContainer.className = 'alert alert-danger alert-dismissible fade show position-fixed top-0 start-50 translate-middle-x mt-3';
      errorContainer.style.zIndex = '1050';
      document.body.appendChild(errorContainer);
    }
    
    // Create the error message HTML
    errorContainer.innerHTML = `
      <div class="d-flex align-items-center">
        <i class="fas fa-exclamation-circle me-2"></i>
        <span>${message}</span>
        <button type="button" class="btn-close ms-auto" data-bs-dismiss="alert" aria-label="Close"></button>
      </div>
    `;
    
    // Make sure the error is visible
    errorContainer.style.display = 'block';
    
    // Auto-hide after 5 seconds
    setTimeout(() => {
      if (errorContainer && errorContainer.parentNode) {
        errorContainer.parentNode.removeChild(errorContainer);
      }
    }, 5000);
  }

  function debugResponses(label) {
    console.log(`--- Responses Map (${label}) ---`);
    console.log(`Total responses: ${responses.size}`);
    responses.forEach((value, key) => {
      console.log(`Question ID: ${key}, Response: ${value}`);
    });
    console.log('------------------------');
  }

  function markQuestionAsAnswered(questionCard, selectedButton) {
    // Remove any previous selections
    questionCard.querySelectorAll('.response-button').forEach(button => {
      button.classList.remove('active', 'btn-primary');
      button.classList.add('btn-outline-primary');
    });
    
    // Mark the selected button
    selectedButton.classList.remove('btn-outline-primary');
    selectedButton.classList.add('active', 'btn-primary');
    
    // Add a visual indicator that the question was answered
    questionCard.classList.add('answered');
  }

  function handleAnswer(event) {
    event.preventDefault();
    const button = event.target.closest('.response-button');
    if (!button) return;
    
    const questionCard = button.closest('.question-card');
    if (!questionCard) {
      console.error('Question card not found');
      return;
    }
    
    const questionId = questionCard.dataset.questionId;
    const response = button.dataset.value;
    const isAttentionCheck = questionCard.dataset.attentionCheck === 'true';
    const questionIndex = parseInt(questionCard.dataset.questionIndex, 10);
    
    // Log information about the question that's being answered
    const questionContainer = document.querySelector('.question-container');
    const totalQuestionsFromData = parseInt(questionContainer.dataset.totalQuestions, 10);
    const isBasicSurvey = document.querySelector('meta[name="survey-type"]')?.getAttribute('content') === 'basic';
    
    console.log('handleAnswer:', {
      questionId,
      questionIndex,
      totalQuestionsFromData,
      isBasicSurvey,
      isLastQuestion: questionIndex === totalQuestionsFromData - 1,
      currentQuestionIndex,
      isAttentionCheck
    });
    
    if (!questionId || !response) {
      console.error('Missing question ID or response value');
      return;
    }
    
    try {
      // Mark the question as answered in the UI
      markQuestionAsAnswered(questionCard, button);
      
      // For attention checks, only validate the answer but don't store it
      if (isAttentionCheck) {
        const correctAnswer = questionCard.dataset.correctAnswer;
        console.log(`Processing attention check question ${questionId}. User selected: ${response}, Correct answer: ${correctAnswer}`);
        
        if (response !== correctAnswer) {
          showAttentionCheckWarning(questionCard);
          return;
        }
        // If attention check is correct, move to next question after a delay
        setTimeout(() => {
          moveToNextQuestion();
        }, 750);
        return;
      }
      
      // Store response in client-side Map only, don't save to server yet
      console.log(`Saving response in map: Question ID ${questionId} = ${response}`);
      
      const oldSize = responses.size;
      responses.set(questionId, response);
      
      if (responses.size === oldSize && oldSize > 0) {
        console.log(`Response was updated for existing question ${questionId}`);
      } else {
        console.log(`New response added for question ${questionId}, map size: ${responses.size}`);
      }
      
      debugResponses('After storing response in client-side Map');
      
      // Update progress
      updateProgress();
      
      // Check if at last question
      if (isBasicSurvey && questionIndex === totalQuestionsFromData - 1) {
        console.log('Last question answered, should move to genre selection next');
      }
      
      // Auto-advance after a short delay
      setTimeout(() => {
        console.log('Auto-advancing after answer with moveToNextQuestion()');
        moveToNextQuestion();
      }, 750);
      
    } catch (error) {
      console.error('Error handling response:', error);
      showError('Failed to save your response. Please try again.');
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
    const isAttentionCheck = currentQuestion.dataset.attentionCheck === 'true';
    
    if (!isAttentionCheck) return true;
    
    const questionId = currentQuestion.dataset.questionId;
    const correctAnswer = currentQuestion.dataset.correctAnswer;
    
    // Check if the question has been answered and if the answer is correct
    const hasResponse = responses.has(questionId);
    const responseValue = hasResponse ? responses.get(questionId) : null;
    const isCorrect = hasResponse && responseValue === correctAnswer;
    
    console.log('Attention check validation:', {
      questionId,
      correctAnswer,
      hasResponse,
      responseValue,
      isCorrect
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
      const isBasicSurvey = document.querySelector('meta[name="survey-type"]')?.getAttribute('content') === 'basic';
      const questionContainer = document.querySelector('.question-container');
      const totalQuestionsFromData = parseInt(questionContainer.dataset.totalQuestions, 10);
      
      console.log('Previous button state:', {
        currentQuestionIndex,
        totalQuestionsFromData,
        isBasicSurvey
      });
      
      // Check if we're at genre selection in basic survey
      if (isBasicSurvey && currentQuestionIndex >= totalQuestionsFromData) {
        // Go back to last question from genre selection
        currentQuestionIndex = totalQuestionsFromData - 1;
        console.log('Going back from genre selection to last question');
      } else if (currentQuestionIndex > 0) {
        // Normal case - go back one question
        currentQuestionIndex--;
      }
      
      showCurrentQuestion();
      updateProgress();
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

  // Make sure the save progress button is properly initialized
  function ensureSaveProgressButton() {
    // For extended survey only
    const isBasicSurvey = document.querySelector('meta[name="survey-type"]')?.getAttribute('content') === 'basic';
    if (isBasicSurvey) {
      console.log('Skipping save progress button setup for basic survey.');
      return; 
    }
    
    // Find the existing button rendered by Rails
    saveProgressButton = document.getElementById('save-progress');
    
    if (!saveProgressButton) {
      // Log an error if the button IS NOT found - it should be rendered by the view
      console.error('Save Progress button (#save-progress) not found in the DOM! Ensure it is rendered by the Rails view for extended surveys.');
      return; // Stop if the essential button is missing
    } else {
      console.log('Found existing Save Progress button');
    }
    
    // Make sure it's visible and add listener if needed
    if (saveProgressButton) {
      // Button visibility is handled in showCurrentQuestion now, just ensure listener is attached

      // Check if listener already added (using a custom attribute)
      if (saveProgressButton.dataset.listenerAttached !== 'true') { 
        saveProgressButton.addEventListener('click', handleSaveProgress);
        saveProgressButton.dataset.listenerAttached = 'true'; // Mark as added
        console.log('Added event listener to Save Progress button');
      } else {
        console.log('Event listener already attached to Save Progress button.');
      }
    }
  }

  // Save progress handler function
  async function handleSaveProgress(event) {
    event.preventDefault();
    try {
      // Call debugQuestionSummary first to log state
      debugQuestionSummary();
      
      // Convert responses Map to an array of objects for API submission
      const responsesArray = [];
      responses.forEach((value, key) => {
        // Convert text values to integers for submission
        let numericValue = value;
        if (typeof value === 'string') {
          const valueMap = {
            'Strongly_Disagree': 1,
            'Disagree': 2,
            'Neutral': 3,
            'Agree': 4,
            'Strongly_Agree': 5
          };
          numericValue = valueMap[value] || value;
        }
        
        responsesArray.push({
          question_id: key,
          response: numericValue
        });
      });
      
      // Log the responses being saved
      console.log('Saving progress with survey responses:', responsesArray);
      
      // Save all accumulated responses at once
      const token = document.querySelector('meta[name="csrf-token"]').content;
      const isBasicSurvey = document.querySelector('meta[name="survey-type"]')?.getAttribute('content') === 'basic';
      
      const result = await fetch('/surveys/save_progress', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': token
        },
        body: JSON.stringify({
          survey_responses: responsesArray,
          save_progress: true,
          type: isBasicSurvey ? 'basic' : 'extended',
        })
      });

      if (!result.ok) {
        const errorData = await result.json();
        throw new Error(errorData.message || 'Failed to save progress');
      }
      
      console.log('Progress saved successfully');
      
      // Debugging Bootstrap and Modal Element
      console.log('Bootstrap object on window:', window.bootstrap);
      const modalElement = document.getElementById('saveProgressModal');
      console.log('Modal element found:', modalElement);

      if (window.bootstrap && modalElement) {
        try {
          // Show the save progress modal using window.bootstrap
          const saveProgressModal = new window.bootstrap.Modal(modalElement);
          saveProgressModal.show();
          console.log('Modal show() called.');
        } catch (modalError) {
          console.error('Error showing Bootstrap modal:', modalError);
          showError("Progress saved, but couldn't show confirmation."); // Show error but acknowledge save
        }
      } else {
        console.error('Bootstrap object or modal element not found!');
        showError("Progress saved, but confirmation couldn't be displayed."); // Fallback message
      }
    } catch (error) {
      console.error('Error saving progress:', error);
      showError("Failed to save progress. Please try again.");
    }
  }

  // Call this at initialization
  ensureSaveProgressButton();

  // Create a success message function
  function showSuccessMessage(message) {
    let successContainer = document.getElementById('success-container');
    
    // Create success container if it doesn't exist
    if (!successContainer) {
      successContainer = document.createElement('div');
      successContainer.id = 'success-container';
      successContainer.className = 'alert alert-success alert-dismissible fade show position-fixed top-0 start-50 translate-middle-x mt-3';
      successContainer.style.zIndex = '1050';
      document.body.appendChild(successContainer);
    }
    
    // Create the success message HTML
    successContainer.innerHTML = `
      <div class="d-flex align-items-center">
        <i class="fas fa-check-circle me-2"></i>
        <span>${message}</span>
        <button type="button" class="btn-close ms-auto" data-bs-dismiss="alert" aria-label="Close"></button>
      </div>
    `;
    
    // Make sure the success message is visible
    successContainer.style.display = 'block';
    
    // Auto-hide after 10 seconds
    setTimeout(() => {
      if (successContainer && successContainer.parentNode) {
        successContainer.parentNode.removeChild(successContainer);
      }
    }, 10000);
  }

  function initializeWithSavedResponses() {
    const questionsNodeList = document.querySelectorAll('.question-card'); // Use local variable
    const totalQuestions = questionsNodeList.length; // Use length from nodelist
    let answeredQuestions = 0;
  
    // Count answered questions (based on class added during initial processing)
    questionsNodeList.forEach(questionCard => {
      if (questionCard.classList.contains('answered')) {
        answeredQuestions++;
      }
    });

    // Get the actual number of non-attention-check questions
    const questionContainer = document.querySelector('.question-container');
    const totalRegularQuestions = questionContainer ? parseInt(questionContainer.dataset.totalQuestions, 10) : totalQuestions;
    
    // Set current question index
    if (answeredQuestions >= totalRegularQuestions) {
      // If all regular questions are answered, go to the last question index
      currentQuestionIndex = totalRegularQuestions - 1;
      console.log(`All ${totalRegularQuestions} questions answered. Setting index to last question: ${currentQuestionIndex}`);
    } else if (answeredQuestions > 0) {
      // Otherwise, start at the first unanswered question (index = count of answered)
      currentQuestionIndex = answeredQuestions;
      console.log(`Starting at question index ${currentQuestionIndex} based on ${answeredQuestions} answered questions`);
    } else {
      // No answered questions found, start at 0 (shouldn't happen if hasResumableProgress was true)
      currentQuestionIndex = 0;
       console.log(`No answered questions found, starting at index 0`);
    }
    
    // Debug questions and responses
    debugQuestionSummary();
    
    // Now these functions are accessible because we are inside initializeSurvey
    showCurrentQuestion(); 
    updateProgress(); 
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

// Update navigation buttons for completion state
function updateNavigationButtonsForCompletion() {
  // Get survey type from meta tag
  const surveyType = document.querySelector('meta[name="survey-type"]')?.getAttribute('content') || 'basic';
  
  // Hide previous and next buttons
  const prevButton = document.querySelector('.btn-prev');
  const nextButton = document.querySelector('.btn-next');
  const completeButton = document.querySelector('.btn-complete');
  
  if (prevButton) prevButton.style.display = 'none';
  if (nextButton) nextButton.style.display = 'none';
  
  // Show and enable complete button
  if (completeButton) {
    completeButton.style.display = 'block';
    completeButton.disabled = false;
    
    // Use "Complete Survey" for both survey types
    completeButton.innerHTML = 'Complete Survey<i class="fas fa-check ms-2"></i>';
  }
  
  // Update progress bar to 100%
  updateProgressBar(100);
  
  // Update question counter to show completion
  const questionCounter = document.getElementById('questionCounter');
  if (questionCounter) {
    questionCounter.textContent = 'Survey Complete';
  }
}

// Function to create the genre selection element if it doesn't exist
function createGenreSelectionElement() {
  // Check if we already have the element
  if (document.getElementById('genre-selection')) {
    console.log('Genre selection element already exists');
    return;
  }
  
  console.log('Creating basic genre selection element');
  
  // Create genre selection container
  const genreSelection = document.createElement('div');
  genreSelection.id = 'genre-selection';
  genreSelection.style.display = 'none'; // Hidden by default
  
  // Add heading and instruction
  const heading = document.createElement('h3');
  heading.className = 'question-text mb-4';
  heading.textContent = 'Final Step: Select Your Favorite Genres';
  
  const instruction = document.createElement('p');
  instruction.className = 'mb-4';
  instruction.textContent = 'Choose the genres you enjoy most (we recommend selecting at least 3):';
  
  // Add genres container
  const genresContainer = document.createElement('div');
  genresContainer.className = 'btn-group-toggle d-flex flex-wrap gap-2';
  genresContainer.setAttribute('data-toggle', 'buttons');
  
  // Common movie genres
  const commonGenres = [
    'Action', 'Adventure', 'Animation', 'Comedy', 'Crime', 'Documentary',
    'Drama', 'Family', 'Fantasy', 'History', 'Horror', 'Music', 'Mystery',
    'Romance', 'Science Fiction', 'Thriller', 'War', 'Western'
  ];
  
  // Create checkboxes for each genre
  commonGenres.forEach(genre => {
    // Create checkbox
    const checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.className = 'btn-check';
    checkbox.id = genre.toLowerCase().replace(/\s+/g, '-');
    checkbox.name = 'favorite_genres[]';
    checkbox.value = genre;
    
    // Create label
    const label = document.createElement('label');
    label.htmlFor = checkbox.id;
    label.className = 'btn btn-outline-primary';
    label.textContent = genre;
    
    // Add to container
    genresContainer.appendChild(checkbox);
    genresContainer.appendChild(label);
  });
  
  // Assemble the elements
  genreSelection.appendChild(heading);
  genreSelection.appendChild(instruction);
  genreSelection.appendChild(genresContainer);
  
  // Add to the survey container
  const surveyContainer = document.querySelector('.survey-container');
  if (surveyContainer) {
    surveyContainer.appendChild(genreSelection);
    console.log('Basic genre selection element added to DOM');
    
    // Force update the Complete button whenever genre selection is created
    setTimeout(() => {
      console.log('Updating navigation buttons for genre selection');
      const completeBtn = document.getElementById('complete-survey');
      const nextButton = document.getElementById('next-button');
      const prevButton = document.getElementById('prev-button');
      
      if (completeBtn) {
        completeBtn.style.display = genreSelection.style.display === 'block' ? 'block' : 'none';
        if (genreSelection.style.display === 'block') {
          console.log('Force-showing Complete button for genre selection');
        }
      }
      
      if (nextButton && genreSelection.style.display === 'block') {
        nextButton.style.display = 'none';
      }
      
      if (prevButton && genreSelection.style.display === 'block') {
        prevButton.style.display = 'block';
      }
    }, 100);
  } else {
    console.error('Survey container not found, cannot add genre selection');
  }
}

// Add debug function to show questions summary
function debugQuestionSummary() {
  const questions = document.querySelectorAll('.question-card');
  const totalQuestions = questions.length;
  const attentionChecks = Array.from(questions).filter(q => q.dataset.attentionCheck === 'true');
  const regularQuestions = Array.from(questions).filter(q => q.dataset.attentionCheck !== 'true');
  
  console.log('--- QUESTIONS SUMMARY ---');
  console.log(`Total questions: ${totalQuestions}`);
  console.log(`Regular questions: ${regularQuestions.length}`);
  console.log(`Attention checks: ${attentionChecks.length}`);
  
  // Log IDs of all questions
  console.log('All question IDs:', Array.from(questions).map(q => q.dataset.questionId));
  
  // Log IDs of attention checks
  console.log('Attention check IDs:', attentionChecks.map(q => q.dataset.questionId));
  
  // Log current responses
  console.log(`Total responses in map: ${responses.size}`);
  console.log('Response IDs:', Array.from(responses.keys()));
  
  // Find missing responses
  const allQuestionIds = Array.from(regularQuestions).map(q => q.dataset.questionId);
  const respondedIds = Array.from(responses.keys());
  const missingIds = allQuestionIds.filter(id => !respondedIds.includes(id));
  console.log('Missing response IDs:', missingIds);
  console.log('------------------------');
}

// Add this new function
function ensureCompleteButtonFunctionality() {
  console.log('Ensuring Complete button functionality');
  let completeBtn = document.getElementById('complete-survey'); 
  
  if (!completeBtn) {
    console.error('Complete button not found in the DOM by ID!');
    completeBtn = document.querySelector('.complete-button'); // Fallback
    if (completeBtn) {
      console.log('Found Complete button with class selector');
      if (!completeBtn.id) completeBtn.id = 'complete-survey'; 
    } else {
      console.error('Cannot find Complete button with any selector');
      return; 
    }
  }

  // Check if the listener is already attached
  if (completeBtn.dataset.listenerAttached === 'true') {
    console.log('Complete button listener already attached.');
    // Ensure correct initial visibility based on current state
    const isBasicSurveyInitCheck = document.querySelector('meta[name="survey-type"]')?.getAttribute('content') === 'basic';
    const questionContainerInitCheck = document.querySelector('.question-container');
    const totalQuestionsFromDataInitCheck = questionContainerInitCheck ? parseInt(questionContainerInitCheck.dataset.totalQuestions, 10) : 0;
    const isLastQuestionInitCheck = !isBasicSurveyInitCheck && currentQuestionIndex === totalQuestionsFromDataInitCheck - 1;
    const genreSelectionElemInitCheck = document.getElementById('genre-selection');
    const isAtGenreSelectionInitCheck = isBasicSurveyInitCheck && genreSelectionElemInitCheck && genreSelectionElemInitCheck.style.display === 'block';
    completeBtn.style.display = (isLastQuestionInitCheck || isAtGenreSelectionInitCheck) ? 'block' : 'none';
    console.log(`Initial visibility check (listener already attached): display=${completeBtn.style.display}`);
    return; // Don't re-attach listener
  }
  
  // Style the button correctly (ensure it has the right classes)
  completeBtn.className = 'btn nav-button complete-button';
  
  console.log('Attaching click listener to Complete button.');
  completeBtn.addEventListener('click', async function(event) {
    event.preventDefault();
    console.log('Complete Survey button click detected'); // <-- CLICK HANDLER ENTRY LOG
    
    try {
      debugQuestionSummary();
      const isBasicSurvey = document.querySelector('meta[name="survey-type"]')?.getAttribute('content') === 'basic';
      const genreSelectionElem = document.getElementById('genre-selection'); // Use local name
      const isAtGenreSelection = isBasicSurvey && genreSelectionElem && genreSelectionElem.style.display === 'block';
      const isRetake = completeBtn.dataset.retake === 'true';
      
      console.log('Complete Survey button state:', {
        isBasicSurvey, hasGenreSelection: !!genreSelectionElem, isAtGenreSelection, 
        genreSelectionDisplay: genreSelectionElem ? genreSelectionElem.style.display : 'N/A', isRetake
      });
      
      if (isAtGenreSelection) {
        const genreCheckboxes = genreSelectionElem.querySelectorAll('input[name="favorite_genres[]"]:checked');
        if (genreCheckboxes.length === 0) {
          showError('Please select at least one favorite genre before completing the survey.');
          return;
        }
      }
      
      const questionContainer = document.querySelector('.question-container');
      const totalQuestionsFromData = questionContainer ? parseInt(questionContainer.dataset.totalQuestions, 10) : 0;

      if (!(isBasicSurvey && currentQuestionIndex >= totalQuestionsFromData)) {
          const questions = document.querySelectorAll('.question-card:not([data-attention-check="true"])');
          const questionIds = Array.from(questions).map(q => q.dataset.questionId);
          const respondedIds = Array.from(responses.keys());
          const missingIds = questionIds.filter(id => !respondedIds.includes(id));
          console.log(`Checking responses completeness: ${responses.size} responses vs ${questions.length} questions`);
          console.log('Missing responses for question IDs:', missingIds);
          
          const requiredCompletionRatio = isBasicSurvey ? 1.0 : 0.9;
          const actualCompletionRatio = questions.length > 0 ? (responses.size / questions.length) : 1.0;
          console.log(`Completion ratio: ${actualCompletionRatio.toFixed(2)} (Required: ${requiredCompletionRatio})`);
          if (actualCompletionRatio < requiredCompletionRatio) {
            showError(`Please answer ${isBasicSurvey ? 'all' : 'at least 90% of the'} questions before completing the survey.`);
            return;
          }
      }
      
      const selectedGenres = [];
      if (isAtGenreSelection) { 
        const genreCheckboxes = genreSelectionElem.querySelectorAll('input[name="favorite_genres[]"]:checked');
        genreCheckboxes.forEach(checkbox => { selectedGenres.push(checkbox.value); });
      }
      
      const responsesArray = [];
      responses.forEach((value, key) => {
        let numericValue = value;
        if (typeof value === 'string') {
          const valueMap = {'Strongly_Disagree': 1, 'Disagree': 2, 'Neutral': 3, 'Agree': 4, 'Strongly_Agree': 5};
          numericValue = valueMap[value] || value; 
        }
        responsesArray.push({ question_id: key, response: numericValue });
      });
      
      console.log('Submitting survey with selected genres:', selectedGenres);
      console.log('Submitting responses:', responsesArray);
      
      const loadingIndicator = document.createElement('div');
      loadingIndicator.className = 'position-fixed top-0 start-0 w-100 h-100 d-flex justify-content-center align-items-center';
      loadingIndicator.style.backgroundColor = 'rgba(0, 0, 0, 0.5)';
      loadingIndicator.style.zIndex = '9999';
      loadingIndicator.innerHTML = `<div class="spinner-border text-light" role="status"><span class="visually-hidden">Loading...</span></div>`;
      document.body.appendChild(loadingIndicator);
      
      const token = document.querySelector('meta[name="csrf-token"]').content;
      console.log('Sending survey data for complete submission:', { survey_responses: responsesArray, favorite_genres: selectedGenres, submit_survey: 'true', type: isBasicSurvey ? 'basic' : 'extended', retake: isRetake });
      
      const saveResult = await fetch('/surveys', {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'Accept': 'application/json', 'X-CSRF-Token': token },
        body: JSON.stringify({ survey_responses: responsesArray, favorite_genres: selectedGenres, submit_survey: 'true', type: isBasicSurvey ? 'basic' : 'extended', retake: isRetake })
      });

      document.body.removeChild(loadingIndicator);

      if (!saveResult.ok) {
        const errorText = await saveResult.text();
        console.error('Error response:', errorText);
        throw new Error(`Failed to save responses: ${saveResult.status} ${errorText}`);
      }
      
      console.log('Survey saved successfully');
      
      try {
        const contentType = saveResult.headers.get('content-type');
        let responseData = null;
        let redirectUrl = null;
        if (contentType && contentType.includes('application/json')) {
          responseData = await saveResult.json();
          console.log('Server response:', responseData);
          redirectUrl = responseData.redirect_url;
        } else {
          console.warn('Response is not JSON, checking Location header', contentType);
          const locationHeader = saveResult.headers.get('location');
          if (locationHeader) { redirectUrl = locationHeader; }
        }

        // Handle extended vs basic survey completion flow
        if (!isBasicSurvey) {
          // === MODIFIED: Redirect immediately for extended survey ===
          const targetUrl = redirectUrl || '/survey_results?type=extended'; // Use redirectUrl if available
          console.log(`Extended survey complete, redirecting to ${targetUrl}`);
          window.location.href = targetUrl;
        } else {
          // Basic Survey: Redirect immediately if URL is available
          const targetUrl = redirectUrl || '/survey_results?type=basic'; // Use redirectUrl if available
          console.log(`Basic survey complete, redirecting to ${targetUrl}`);
          window.location.href = targetUrl;
        }
        
      } catch (jsonError) {
        console.warn('Post-processing/JSON parsing error, proceeding with fallback redirect', jsonError);
        window.location.href = isBasicSurvey ? '/survey_results?type=basic' : '/survey_results?type=extended';
      }
      
    } catch (error) {
      console.error('Error in Complete Survey handler:', error);
      const loadingIndicator = document.querySelector('.spinner-border')?.closest('div[style*="background-color: rgba(0, 0, 0, 0.5)"]');
      if (loadingIndicator && loadingIndicator.parentNode) document.body.removeChild(loadingIndicator);
      showError('Failed to complete the survey. Please try again.');
    }
  });
  
  // Mark the listener as attached
  completeBtn.dataset.listenerAttached = 'true';
  console.log('Complete button listener attached successfully.');
  
  // Set initial visibility after attaching listener
  const isBasicSurveyInit = document.querySelector('meta[name="survey-type"]')?.getAttribute('content') === 'basic';
  const questionContainerInit = document.querySelector('.question-container');
  const totalQuestionsFromDataInit = questionContainerInit ? parseInt(questionContainerInit.dataset.totalQuestions, 10) : 0;
  const isLastQuestionInit = !isBasicSurveyInit && currentQuestionIndex === totalQuestionsFromDataInit - 1;
  const genreSelectionElemInit = document.getElementById('genre-selection');
  const isAtGenreSelectionInit = isBasicSurveyInit && genreSelectionElemInit && genreSelectionElemInit.style.display === 'block';

  completeBtn.style.display = (isLastQuestionInit || isAtGenreSelectionInit) ? 'block' : 'none';
  console.log(`Initial visibility set in ensureCompleteButtonFunctionality: display=${completeBtn.style.display}`);
}





function moveToNextQuestion() {
  const questionContainer = document.querySelector('.question-container');
  if (!questionContainer) {
    console.error('Question container not found in moveToNextQuestion');
    return;
  }
  
  const totalQuestionsFromData = parseInt(questionContainer.dataset.totalQuestions, 10);
  const isBasicSurvey = document.querySelector('meta[name="survey-type"]')?.getAttribute('content') === 'basic';
  const isCurrentlyLastQuestion = currentQuestionIndex === totalQuestionsFromData - 1; 
  const shouldShowGenreSelection = isBasicSurvey && isCurrentlyLastQuestion; 
  
  console.log('moveToNextQuestion debug:', {
    currentQuestionIndex, totalQuestionsFromData, isBasicSurvey, isCurrentlyLastQuestion, shouldShowGenreSelection
  });
  
  // Basic Survey: Moving from last question to genre selection?
  if (shouldShowGenreSelection) { 
    console.log('Moving from last basic question to genre selection step');
    currentQuestionIndex = totalQuestionsFromData; // Genre state index
    
    genreSelection = document.getElementById('genre-selection');
    console.log('Genre selection element:', !!genreSelection);
    
    showCurrentQuestion(); 
    updateProgress(); 
    return; 
  }
  
  // Moving to next question (not genre step)
  if (currentQuestionIndex < totalQuestionsFromData - 1) {
    currentQuestionIndex++;
    console.log(`Moving to question index: ${currentQuestionIndex}`);
    showCurrentQuestion(); 
    updateProgress();
  } else if (currentQuestionIndex === totalQuestionsFromData - 1) {
    // Already at last question (e.g., extended survey done answering)
    console.log('Already at last question index, ensuring UI state for completion.');
    showCurrentQuestion(); // Ensure Complete button shows
    updateProgress(); 
  } else {
    // Index is >= totalQuestions (should be genre selection state)
    console.warn(`moveToNextQuestion called with index >= total questions: ${currentQuestionIndex}. Assuming genre selection.`);
    showCurrentQuestion(); // Ensure genre view is displayed
    updateProgress();
  }
}

// ... existing code ...
