import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["question", "progress", "nextButton", "prevButton", "submitButton", "genreSelection"]
  
  connect() {
    console.log("Survey controller connected")
    this.currentQuestionIndex = 0
    this.totalQuestions = this.questionTargets.length
    console.log("Total questions:", this.totalQuestions)
    this.responses = new Map()
    this.attentionCheckInterval = this.element.dataset.surveyType === 'extended' ? 15 : 8
    this.lastAttentionCheck = 0
    
    this.updateNavigationButtons()
    this.showCurrentQuestion()
    
    // Auto-save for extended survey
    if (document.querySelector('[data-survey-type="extended"]')) {
      this.setupAutoSave()
    }
  }

  next() {
    if (this.validateCurrentQuestion()) {
      if (this.shouldShowAttentionCheck()) {
        this.showAttentionCheck()
      } else {
        this.moveToNextQuestion()
      }
    }
  }

  prev() {
    this.currentQuestionIndex--
    this.showCurrentQuestion()
    this.updateNavigationButtons()
  }

  validateCurrentQuestion() {
    const currentQuestion = this.questionTargets[this.currentQuestionIndex]
    const selectedOption = currentQuestion.querySelector('input[type="radio"]:checked')
    
    if (!selectedOption) {
      this.showError("Please select an answer before proceeding.")
      return false
    }
    
    if (currentQuestion.dataset.attentionCheck === 'true') {
      const correctAnswer = currentQuestion.dataset.correctAnswer
      if (selectedOption.value !== correctAnswer) {
        this.showError("Incorrect attention check response. Please read the question carefully and try again.")
        return false
      }
    }
    
    this.responses.set(currentQuestion.dataset.questionId, selectedOption.value)
    return true
  }

  moveToNextQuestion() {
    this.currentQuestionIndex++
    
    if (this.currentQuestionIndex >= this.totalQuestions) {
      this.showGenreSelection()
    } else {
      this.showCurrentQuestion()
    }
    
    this.updateNavigationButtons()
    this.updateProgress()
  }

  showCurrentQuestion() {
    this.questionTargets.forEach((question, index) => {
      question.style.display = index === this.currentQuestionIndex ? 'block' : 'none'
    })
    this.genreSelectionTarget.style.display = 'none'
  }

  showGenreSelection() {
    this.questionTargets.forEach(question => question.style.display = 'none')
    this.genreSelectionTarget.style.display = 'block'
    this.nextButtonTarget.style.display = 'none'
    this.submitButtonTarget.style.display = 'block'
  }

  updateNavigationButtons() {
    this.prevButtonTarget.style.display = this.currentQuestionIndex > 0 ? 'block' : 'none'
    this.nextButtonTarget.style.display = this.currentQuestionIndex < this.totalQuestions ? 'block' : 'none'
  }

  updateProgress() {
    const progress = ((this.currentQuestionIndex + 1) / (this.totalQuestions + 1)) * 100
    this.progressTarget.style.width = `${progress}%`
    this.progressTarget.setAttribute('aria-valuenow', progress)
    this.progressTarget.textContent = `${Math.round(progress)}%`
  }

  shouldShowAttentionCheck() {
    return this.currentQuestionIndex - this.lastAttentionCheck >= this.attentionCheckInterval
  }

  showAttentionCheck() {
    const attentionCheck = {
      question: "Please select 'Agree' for this attention check question.",
      correctAnswer: "Agree"
    }

    const response = this.showAttentionCheckModal(attentionCheck)
    if (response === attentionCheck.correctAnswer) {
      this.lastAttentionCheck = this.currentQuestionIndex
      this.moveToNextQuestion()
    } else {
      this.showError("Incorrect attention check response. Please pay attention to the questions.")
    }
  }

  setupAutoSave() {
    setInterval(() => {
      if (this.responses.size > 0) {
        this.saveProgress()
      }
    }, 30000) // Auto-save every 30 seconds
  }

  async saveProgress() {
    try {
      const response = await fetch('/surveys/save_progress', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({
          personality_responses: Object.fromEntries(this.responses)
        })
      })

      if (!response.ok) throw new Error('Failed to save progress')
      
      this.showMessage("Progress saved successfully!", "success")
    } catch (error) {
      console.error('Error saving progress:', error)
      this.showMessage("Failed to save progress. Please try again.", "error")
    }
  }

  showMessage(message, type) {
    const alertDiv = document.createElement('div')
    alertDiv.className = `alert alert-${type} alert-dismissible fade show`
    alertDiv.innerHTML = `
      ${message}
      <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
    `
    document.querySelector('.card-body').insertBefore(alertDiv, document.querySelector('#survey-form'))
    setTimeout(() => alertDiv.remove(), 3000)
  }

  showError(message) {
    this.showMessage(message, "danger")
  }

  async selectAnswer(event) {
    console.log("Answer selected:", event.currentTarget.dataset.value)
    const button = event.currentTarget
    const value = button.dataset.value
    const questionId = button.closest('[data-question-id]').dataset.questionId

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
      })

      if (!response.ok) {
        throw new Error('Failed to save response')
      }

      // Store response locally
      this.responses.set(questionId, value)
      
      // Move to next question
      this.next()
    } catch (error) {
      console.error('Error saving response:', error)
    }
  }
} 
