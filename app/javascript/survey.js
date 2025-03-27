const RESPONSE_VALUES = {
  'Strongly_Disagree': 1,
  'Disagree': 2,
  'Neutral': 3,
  'Agree': 4,
  'Strongly_Agree': 5
};

// Global variables and helper functions
let currentQuestionIndex = 0;
let progressBar, prevButton, nextButton, genreSelection, completeBtn, responses, saveProgressButton;

document.addEventListener('DOMContentLoaded', () => {
  console.log('DOM loaded, initializing survey components');
  
  // Initialize welcome modal independently
  initializeWelcomeModal();
  
  // Initialize survey form if it exists
  initializeSurvey();
  
  // Check if we need to immediately show the genre selection screen
  setTimeout(() => {
    checkInitialGenreSelectionState();
  }, 200);
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
    const savedResponse = questionCard.dataset.savedResponse;
    
    if (savedResponse) {
      // Add to responses Map
      responses.set(questionId, savedResponse);
      
      // Find and highlight the button
      const button = questionCard.querySelector(`.response-button[data-value="${savedResponse}"]`);
      if (button) {
        markQuestionAsAnswered(questionCard, button);
        hasResumableProgress = true;
      }
    }
  });
  
  // If there are saved responses, initialize to the next unanswered question
  if (hasResumableProgress) {
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
    let genreSelection = document.getElementById('genre-selection');
    let completeBtn = document.getElementById('complete-survey');
    let nextButton = document.getElementById('next-button');
    let prevButton = document.getElementById('prev-button');
    let saveProgressButton = document.getElementById('save-progress');
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

    // Create complete button if it doesn't exist
    if (!completeBtn) {
      console.log('Complete button not found in showCurrentQuestion, creating it');
      completeBtn = document.createElement('button');
      completeBtn.type = 'button';
      completeBtn.id = 'complete-survey';
      completeBtn.className = 'btn nav-button complete-button';
      completeBtn.innerHTML = 'Complete Survey<i class="fas fa-check ms-2"></i>';
      completeBtn.dataset.retake = document.querySelector('meta[name="retake"]')?.getAttribute('content') || 'false';
      completeBtn.style.display = 'none'; // Hidden by default
      
      // Add to navigation container
      navContainer.appendChild(completeBtn);
      console.log('Created complete button and added to navigation container in showCurrentQuestion');
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
        console.error('Complete button still not found after creation attempt in showCurrentQuestion!');
      }
      if (saveProgressButton) {
        saveProgressButton.style.display = 'none';
      }
      
      // Ensure the navigation container is visible
      navContainer.style.display = 'flex';
      console.log('Navigation container displayed in showCurrentQuestion');
      
      // Make sure the complete button has an event handler for genre selection
      if (completeBtn) {
        // Remove any existing event listeners by cloning
        const newCompleteBtn = completeBtn.cloneNode(true);
        completeBtn.parentNode.replaceChild(newCompleteBtn, completeBtn);
        completeBtn = newCompleteBtn;
        
        completeBtn.addEventListener('click', async function(event) {
          event.preventDefault();
          console.log('Complete button clicked from genre selection (attached in showCurrentQuestion)');
          
          // Check if genre selection exists
          if (!genreSelection) {
            console.error('Genre selection not found when Complete button clicked!');
            return;
          }
          
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
            console.log('Sending survey data for complete submission:', {
              survey_responses: responsesArray,
              favorite_genres: selectedGenres,
              submit_survey: 'true',
              type: isBasicSurvey ? 'basic' : 'extended',
              debug_info: debugInfo,
              send_debug_email: true,
              retake: isRetake
            });
            
            // Submit all responses at once
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
                type: isBasicSurvey ? 'basic' : 'extended',
                debug_info: debugInfo,
                send_debug_email: true,
                retake: isRetake
              })
            });
            
            // Remove loading indicator
            document.body.removeChild(loadingIndicator);
            
            if (!saveResult.ok) {
              throw new Error(`Failed to save responses: ${saveResult.status}`);
            }
            
            console.log('Survey saved successfully');
            
            // Try to parse the response as JSON
            const responseData = await saveResult.json();
            console.log('Server response:', responseData);
            
            if (responseData.redirect_url) {
              // Follow the server's redirect
              window.location.href = responseData.redirect_url;
            } else {
              // Fallback redirect
              window.location.href = '/survey_results?type=basic';
            }
          } catch (error) {
            console.error('Error completing survey:', error);
            showError('Failed to complete the survey. Please try again.');
          }
        });
      }
      
      return;
    }

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
          completeBtn.textContent = 'Complete Extended Survey';
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
        // For any survey, ensure proper button order
        if (prevButton) {
          // First ensure all buttons are in the DOM
          const allButtons = [prevButton];
          
          // For extended survey, add Save Progress button
          if (!isBasicSurvey && saveProgressButton) {
            if (!navButtonsContainer.contains(saveProgressButton)) {
              console.log('Save Progress button not in DOM, attempting to add it');
              navButtonsContainer.appendChild(saveProgressButton);
            }
            allButtons.push(saveProgressButton);
          }
          
          // Add appropriate final button (next or complete)
          if (isLastQuestion && !isBasicSurvey && completeBtn) {
            // Extended survey last question: complete button
            allButtons.push(completeBtn);
          } else if (nextButton) {
            // Either non-last question or basic survey last question: next button
            allButtons.push(nextButton);
          }
          
          // Ensure proper visible order
          navButtonsContainer.innerHTML = '';
          allButtons.forEach(button => {
            navButtonsContainer.appendChild(button);
          });
          
          console.log('Reordered navigation buttons');
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

  function moveToNextQuestion() {
    const questionContainer = document.querySelector('.question-container');
    if (!questionContainer) {
      console.error('Question container not found in moveToNextQuestion');
      return;
    }
    
    const totalQuestionsFromData = parseInt(questionContainer.dataset.totalQuestions, 10);
    const isBasicSurvey = document.querySelector('meta[name="survey-type"]')?.getAttribute('content') === 'basic';
    const shouldShowGenreSelection = isBasicSurvey && currentQuestionIndex >= totalQuestionsFromData - 1;
    const isLastQuestion = currentQuestionIndex >= totalQuestionsFromData - 1;
    
    console.log('moveToNextQuestion debug:', {
      currentQuestionIndex,
      totalQuestionsFromData,
      isBasicSurvey,
      shouldShowGenreSelection,
      isLastQuestion
    });
    
    // For basic survey, check if we should move to genre selection
    if (shouldShowGenreSelection && isBasicSurvey) {
      console.log('Moving to genre selection');
      currentQuestionIndex = totalQuestionsFromData; // This will trigger genre selection display
      
      // Check if genre selection element exists
      let genreSelection = document.getElementById('genre-selection');
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
        let prevButton = document.getElementById('prev-button');
        let nextButton = document.getElementById('next-button');
        let completeBtn = document.getElementById('complete-survey');
        
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
          completeBtn.parentNode.replaceChild(newCompleteBtn, completeBtn);
          completeBtn = newCompleteBtn;
          
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
                // Try to parse the response as JSON
                const responseData = await saveResult.json();
                console.log('Server response:', responseData);
                
                if (responseData.redirect_url) {
                  // For basic survey, follow the server's redirect
                  console.log(`Redirecting to ${responseData.redirect_url}`);
                  window.location.href = responseData.redirect_url;
                  return;
                }
              } catch (jsonError) {
                console.warn('Could not parse response as JSON, proceeding with default behavior', jsonError);
              }

              // Show completion modal for extended survey only if no redirect was provided
              if (!isBasicSurvey) {
                const surveyCompletionModal = new bootstrap.Modal(document.getElementById('surveyCompletionModal'));
                surveyCompletionModal.show();
                
                // Add event listener to redirect to results page when modal is closed
                const modalElement = document.getElementById('surveyCompletionModal');
                modalElement.addEventListener('hidden.bs.modal', () => {
                  window.location.href = '/survey_results?type=extended';
                });
              } else {
                // For basic survey fallback, redirect directly to results page
                window.location.href = '/survey_results?type=basic';
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
        }, 500);
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
    if (isBasicSurvey) return;
    
    if (!saveProgressButton) {
      console.log('Save Progress button not initialized, attempting to find it');
      saveProgressButton = document.getElementById('save-progress');
      
      if (!saveProgressButton) {
        console.log('Still not found with ID, trying class selector');
        saveProgressButton = document.querySelector('.save-progress-button');
      }
      
      if (!saveProgressButton) {
        console.log('Save Progress button not found, creating it');
        saveProgressButton = document.createElement('button');
        saveProgressButton.id = 'save-progress';
        saveProgressButton.className = 'btn nav-button save-progress-button';
        saveProgressButton.innerHTML = '<i class="fas fa-save me-2"></i>Save Progress';
        
        // Add it to the navigation container
        const navContainer = document.querySelector('.navigation-buttons');
        if (navContainer) {
          const nextButton = document.getElementById('next-button');
          if (nextButton && nextButton.parentNode) {
            navContainer.insertBefore(saveProgressButton, nextButton);
            console.log('Created and added Save Progress button');
          }
        }
      }
      
      // Make sure it's visible
      if (saveProgressButton) {
        saveProgressButton.style.display = 'block';
        
        // Add event listener if needed
        if (!saveProgressButton.hasEventListener) {
          saveProgressButton.addEventListener('click', handleSaveProgress);
          saveProgressButton.hasEventListener = true;
          console.log('Added event listener to Save Progress button');
        }
      }
    }
  }

  // Save progress handler function
  async function handleSaveProgress() {
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
      
      // Create debug info for email
      const questions = document.querySelectorAll('.question-card:not([data-attention-check="true"])');
      const questionIds = Array.from(questions).map(q => q.dataset.questionId);
      const respondedIds = Array.from(responses.keys());
      const missingIds = questionIds.filter(id => !respondedIds.includes(id));
      
      const debugInfo = {
        total_questions: questions.length,
        total_responses: responses.size,
        missing_count: missingIds.length,
        missing_ids: missingIds,
        completion_percentage: Math.round((responses.size / questions.length) * 100),
        current_question_index: currentQuestionIndex,
        responses: Object.fromEntries(responses)
      };
      
      console.log('Saving progress with survey responses:', {
        survey_responses: responsesArray,
        debug_info: debugInfo
      });
      
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
          debug_info: debugInfo, // Include debug info
          send_debug_email: true // Flag to send debug email
        })
      });

      if (!result.ok) {
        const errorData = await result.json();
        throw new Error(errorData.message || 'Failed to save progress');
      }
      
      console.log('Progress saved successfully');
      
      // Show the save progress modal
      const saveProgressModal = new bootstrap.Modal(document.getElementById('saveProgressModal'));
      saveProgressModal.show();
    } catch (error) {
      console.error('Error saving progress:', error);
      showError("Failed to save progress. Please try again.");
    }
  }

  // Call this at initialization
  ensureSaveProgressButton();

  // Add event listener for save progress button
  if (saveProgressButton) {
    saveProgressButton.addEventListener('click', handleSaveProgress);
  } else {
    console.error('Save Progress button not found during event listener setup');
  }

  // Make sure the Complete button has an event listener
  if (completeBtn) {
    // First remove any existing listeners to avoid duplicates
    const newCompleteBtn = completeBtn.cloneNode(true);
    completeBtn.parentNode.replaceChild(newCompleteBtn, completeBtn);
    completeBtn = newCompleteBtn;
    
    completeBtn.addEventListener('click', async function(event) {
      console.log('Complete Survey button click detected');
      event.preventDefault();
      console.log('Complete Survey button clicked');
      
      try {
        // Debug the question state
        debugQuestionSummary();
        
        // Check if we need to collect genre preferences for basic survey
        const isBasicSurvey = document.querySelector('meta[name="survey-type"]')?.getAttribute('content') === 'basic';
        const genreSelection = document.getElementById('genre-selection');
        const isAtGenreSelection = isBasicSurvey && genreSelection && genreSelection.style.display === 'block';
        
        // Get retake status from button data attribute
        const isRetake = completeBtn.dataset.retake === 'true';
        
        // Log the state when Complete Survey is clicked
        console.log('Complete Survey button state:', {
          isBasicSurvey,
          hasGenreSelection: !!genreSelection,
          isAtGenreSelection,
          genreSelectionDisplay: genreSelection ? genreSelection.style.display : 'N/A',
          isRetake
        });
        
        // Check if we're on the genre selection screen for basic survey
        if (isAtGenreSelection) {
          const genreCheckboxes = document.querySelectorAll('input[name="favorite_genres[]"]:checked');
          console.log('Selected genres:', Array.from(genreCheckboxes).map(cb => cb.value));
          
          if (genreCheckboxes.length === 0) {
            showError('Please select at least one favorite genre before completing the survey.');
            return;
          }
        }
        
        // For basic survey, skip question checking when at genre selection screen
        if (isBasicSurvey && currentQuestionIndex >= parseInt(document.querySelector('.question-container').dataset.totalQuestions, 10)) {
          // At genre selection stage, proceed without checking questions
          console.log('At genre selection - proceeding with submission');
        } else {
          // Find all missing questions
          const questions = document.querySelectorAll('.question-card:not([data-attention-check="true"])');
          const questionIds = Array.from(questions).map(q => q.dataset.questionId);
          const respondedIds = Array.from(responses.keys());
          const missingIds = questionIds.filter(id => !respondedIds.includes(id));
          
          console.log(`Checking responses completeness: ${responses.size} responses vs ${questions.length} questions`);
          console.log('Missing responses for question IDs:', missingIds);
          
          // For extended survey, allow submission with 90% completion
          const requiredCompletionRatio = isBasicSurvey ? 1.0 : 0.9;
          const completionRatio = responses.size / questions.length;
          
          if (completionRatio < requiredCompletionRatio) {
            showError(`Please answer ${isBasicSurvey ? 'all' : 'more'} questions before completing the survey.`);
            return;
          }
        }
        
        // Collect selected genres
        const selectedGenres = [];
        if (isBasicSurvey && genreSelection) {
          const genreCheckboxes = document.querySelectorAll('input[name="favorite_genres[]"]:checked');
          genreCheckboxes.forEach(checkbox => {
            selectedGenres.push(checkbox.value);
          });
        }
        
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
        
        // Create debug info for email
        const questions = document.querySelectorAll('.question-card:not([data-attention-check="true"])');
        const questionIds = Array.from(questions).map(q => q.dataset.questionId);
        const respondedIds = Array.from(responses.keys());
        const missingIds = questionIds.filter(id => !respondedIds.includes(id));
        
        const debugInfo = {
          total_questions: questions.length,
          total_responses: responses.size,
          missing_count: missingIds.length,
          missing_ids: missingIds,
          completion_percentage: Math.round((responses.size / questions.length) * 100),
          current_question_index: currentQuestionIndex,
          responses: Object.fromEntries(responses)
        };
        
        console.log('Submitting survey with selected genres:', selectedGenres);
        console.log('Submitting responses:', responsesArray);
        
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
        
        // Submit all responses at once
        const token = document.querySelector('meta[name="csrf-token"]').content;
        
        // Log data being sent
        console.log('Sending survey data for complete submission:', {
          survey_responses: responsesArray,
          favorite_genres: selectedGenres,
          submit_survey: 'true',
          type: isBasicSurvey ? 'basic' : 'extended',
          debug_info: debugInfo,
          send_debug_email: true,
          retake: isRetake
        });
        
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
            type: isBasicSurvey ? 'basic' : 'extended',
            debug_info: debugInfo,
            send_debug_email: true,
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
          // Try to parse the response as JSON
          const responseData = await saveResult.json();
          console.log('Server response:', responseData);
          
          if (responseData.redirect_url) {
            // For basic survey, follow the server's redirect
            console.log(`Redirecting to ${responseData.redirect_url}`);
            window.location.href = responseData.redirect_url;
            return;
          }
        } catch (jsonError) {
          console.warn('Could not parse response as JSON, proceeding with default behavior', jsonError);
        }

        // Show completion modal for extended survey only if no redirect was provided
        if (!isBasicSurvey) {
          const surveyCompletionModal = new bootstrap.Modal(document.getElementById('surveyCompletionModal'));
          surveyCompletionModal.show();
          
          // Add event listener to redirect to results page when modal is closed
          const modalElement = document.getElementById('surveyCompletionModal');
          modalElement.addEventListener('hidden.bs.modal', () => {
            window.location.href = '/survey_results?type=extended';
          });
        } else {
          // For basic survey fallback, redirect directly to results page
          window.location.href = '/survey_results?type=basic';
        }
        
      } catch (error) {
        console.error('Error completing survey:', error);
        showError('Failed to complete the survey. Please try again.');
      }
    });
  }

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
    
    // Update button text based on survey type
    if (surveyType === 'basic') {
      completeButton.textContent = 'Complete Survey';
    } else {
      completeButton.textContent = 'Complete Extended Survey';
    }
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

// Function to initialize survey with saved responses
function initializeWithSavedResponses() {
  const questions = document.querySelectorAll('.question-card');
  let answeredQuestions = 0;
  
  // Count answered questions to determine the starting position
  questions.forEach(questionCard => {
    if (questionCard.classList.contains('answered')) {
      answeredQuestions++;
    }
  });
  
  // Set current question index to the first unanswered question
  if (answeredQuestions > 0) {
    currentQuestionIndex = answeredQuestions;
    console.log(`Starting at question ${currentQuestionIndex + 1} based on ${answeredQuestions} answered questions`);
  }
  
  // Debug questions and responses
  debugQuestionSummary();
  
  showCurrentQuestion();
  updateProgress();
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
  completeBtn = document.getElementById('complete-survey');
  
  if (!completeBtn) {
    console.error('Complete button not found in the DOM!');
    
    // Try to find it with a broader selector
    completeBtn = document.querySelector('.complete-button');
    if (completeBtn) {
      console.log('Found Complete button with class selector');
    } else {
      console.error('Cannot find Complete button with any selector');
      return;
    }
  }
  
  // Initialize Complete button with correct visibility
  console.log('Initializing Complete button with correct styles and event handlers');
  
  // Remove any existing handlers by cloning
  const newCompleteBtn = completeBtn.cloneNode(true);
  completeBtn.parentNode.replaceChild(newCompleteBtn, completeBtn);
  completeBtn = newCompleteBtn;
  
  // Style the button correctly
  completeBtn.className = 'btn nav-button complete-button';
  completeBtn.id = 'complete-survey';
  
  // Check if we're at genre selection
  const questionContainer = document.querySelector('.question-container');
  const totalQuestionsFromData = questionContainer ? parseInt(questionContainer.dataset.totalQuestions, 10) : 0;
  const isBasicSurvey = document.querySelector('meta[name="survey-type"]')?.getAttribute('content') === 'basic';
  const genreSelection = document.getElementById('genre-selection');
  const isAtGenreSelection = isBasicSurvey && genreSelection && genreSelection.style.display === 'block';
  
  // Set initial visibility based on position
  if (isAtGenreSelection) {
    completeBtn.style.display = 'block';
    console.log('Complete button shown for genre selection during initialization');
  } else {
    completeBtn.style.display = 'none';
    console.log('Complete button hidden during initialization (not at genre selection)');
  }
  
  console.log('Complete button initialized successfully');
}

// Function to check if we need to jump to genre selection on page load
function checkInitialGenreSelectionState() {
  // Get survey type
  const isBasicSurvey = document.querySelector('meta[name="survey-type"]')?.getAttribute('content') === 'basic';
  if (!isBasicSurvey) return;
  
  // Check if initial URL has genre_selection parameter
  const urlParams = new URLSearchParams(window.location.search);
  const showGenreSelection = urlParams.get('genre_selection') === 'true';
  
  // Check for genre selection in DOM
  const genreSelection = document.getElementById('genre-selection');
  if (!genreSelection) return;
  
  // Check if we should show genre selection
  if (showGenreSelection) {
    console.log('URL parameter indicates we should show genre selection');
    
    // Hide all question cards
    document.querySelectorAll('.question-card').forEach(card => {
      card.style.display = 'none';
    });
    
    // Show genre selection
    genreSelection.style.display = 'block';
    
    // Get navigation container
    const navContainer = document.querySelector('.navigation-buttons');
    if (!navContainer) {
      console.error('Navigation container not found in checkInitialGenreSelectionState');
      return;
    }
    
    // Update navigation buttons
    let prevButton = document.getElementById('prev-button');
    let nextButton = document.getElementById('next-button');
    let completeBtn = document.getElementById('complete-survey');
    
    // Create complete button if it doesn't exist
    if (!completeBtn) {
      console.log('Complete button not found in checkInitialGenreSelectionState, creating it');
      completeBtn = document.createElement('button');
      completeBtn.type = 'button';
      completeBtn.id = 'complete-survey';
      completeBtn.className = 'btn nav-button complete-button';
      completeBtn.innerHTML = 'Complete Survey<i class="fas fa-check ms-2"></i>';
      completeBtn.dataset.retake = document.querySelector('meta[name="retake"]')?.getAttribute('content') || 'false';
      
      // Add to navigation container
      navContainer.appendChild(completeBtn);
      console.log('Created complete button and added to navigation container in checkInitialGenreSelectionState');
    }
    
    if (prevButton) prevButton.style.display = 'block';
    if (nextButton) nextButton.style.display = 'none';
    if (completeBtn) {
      completeBtn.style.display = 'block';
      completeBtn.innerHTML = 'Complete Survey<i class="fas fa-check ms-2"></i>';
      console.log('Complete button displayed for initial genre selection');
      
      // Ensure the complete button has an event handler
      const newCompleteBtn = completeBtn.cloneNode(true);
      completeBtn.parentNode.replaceChild(newCompleteBtn, completeBtn);
      completeBtn = newCompleteBtn;
      
      // Add event handler (similar to the one in showCurrentQuestion)
      completeBtn.addEventListener('click', async function(event) {
        event.preventDefault();
        console.log('Complete button clicked from initial genre selection');
        
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
          console.log('Sending survey data from checkInitialGenreSelectionState handler:', {
            survey_responses: responsesArray,
            favorite_genres: selectedGenres,
            submit_survey: 'true',
            type: 'basic',
            retake: isRetake
          });
          
          // Submit all responses at once
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
            throw new Error(`Failed to save responses: ${saveResult.status}`);
          }
          
          console.log('Survey saved successfully');
          
          // Try to parse the response as JSON
          const responseData = await saveResult.json();
          console.log('Server response:', responseData);
          
          if (responseData.redirect_url) {
            // Follow the server's redirect
            window.location.href = responseData.redirect_url;
          } else {
            // Fallback redirect
            window.location.href = '/survey_results?type=basic';
          }
        } catch (error) {
          console.error('Error completing survey:', error);
          showError('Failed to complete the survey. Please try again.');
        }
      });
    }
    
    // Hide question counter
    const questionCounter = document.querySelector('.text-muted');
    if (questionCounter) {
      questionCounter.style.display = 'none';
    }
    
    // Set current question index to trigger genre selection in the JS model
    const questionContainer = document.querySelector('.question-container');
    if (questionContainer) {
      const totalQuestionsFromData = parseInt(questionContainer.dataset.totalQuestions, 10);
      currentQuestionIndex = totalQuestionsFromData;
    }
    
    console.log('Genre selection screen initialized on page load');
  }
} 
