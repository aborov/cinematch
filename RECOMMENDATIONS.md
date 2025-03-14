# CineMatch Recommendation System

## Overview

CineMatch offers two recommendation approaches:

1. **Traditional Psychological Profiling**: Uses personality traits and preferences to match users with content genres.
2. **AI-Powered Recommendations**: Leverages LLMs to generate personalized recommendations based on user profile data.

This document focuses on the traditional psychological profiling approach and how it creates scientifically sound matches between users and content.

## Traditional Recommendation System

### Data Sources

The traditional recommendation system incorporates:

- **Big Five Personality Traits**: Openness, Conscientiousness, Extraversion, Agreeableness, and Neuroticism
- **Emotional Intelligence**: Recognition, Management, Understanding, and Adaptation
- **User Preferences**: Explicitly stated favorite genres
- **Extended Psychological Traits** (when available):
  - HEXACO: Focus on Honesty-Humility dimension
  - Attachment Style: Secure, Anxious, Avoidant, Fearful-Avoidant
  - Moral Foundations: Care, Fairness, Loyalty, Authority, Purity
  - Cognitive Style: Visual vs. Verbal, Systematic vs. Intuitive, Abstract vs. Concrete

### Matching Algorithm

The matching algorithm employs a weighted scoring system that adapts based on data availability:

#### Basic Profile (Basic Survey Only)
- 50% Big Five personality traits
- 40% Favorite genres
- 10% Emotional intelligence

#### Extended Profile (Extended Survey Completed)
- 30% Big Five personality traits
- 30% Favorite genres
- 10% Emotional intelligence
- 10% HEXACO (primarily Honesty-Humility)
- 10% Attachment style
- 5% Moral foundations
- 5% Cognitive style

### Scientific Basis

#### Big Five and Genre Mapping

| Personality Trait | Associated Genres |
|-------------------|-------------------|
| Openness | Science-Fiction, Fantasy, Animation |
| Conscientiousness | Drama, Biography, History |
| Extraversion | Comedy, Action, Adventure |
| Agreeableness | Romance, Family, Music |
| Neuroticism | Thriller, Mystery, Horror |

#### HEXACO Influences

- **Highly Principled/Principled**: Higher scores for content with clear moral messages (Drama, Biography, History, War)
- **Pragmatic/Opportunistic**: Higher scores for morally ambiguous content (Crime, Thriller, Mystery)

#### Attachment Style Influences

- **Secure**: Balanced preference across genres
- **Anxious**: Higher scores for emotional and relationship-focused content (Romance, Drama)
- **Avoidant**: Higher scores for action-oriented and less emotional content (Action, Adventure, Thriller)
- **Fearful-Avoidant**: Higher scores for complex narratives (Drama, Mystery, Science-Fiction)

#### Emotional Intelligence Influences

- **Exceptional/Strong**: Higher scores for emotionally complex content (Drama, Thriller, Mystery)
- **Moderate**: Higher scores for content with clear emotional themes (Drama, Romance, Family)
- **Developing**: Higher scores for lighter or more straightforward content (Comedy, Action, Adventure)

### Implementation Details

The recommendation process follows these steps:

1. Retrieve the user's personality profile data
2. Calculate base scores from Big Five traits and favorite genres
3. Incorporate additional psychological traits if available
4. Apply appropriate weights based on profile depth
5. Normalize scores to a 0-100 scale
6. Sort content by match score
7. Return the top 100 matches

## Advantages Over Simple Genre Matching

This system offers several advantages over simple genre-based recommendations:

1. **Deeper Personalization**: Incorporates multiple dimensions of personality beyond stated preferences
2. **Scientific Foundation**: Based on established psychological theories and research
3. **Adaptability**: Provides valuable recommendations even with minimal data, but improves with more information
4. **Cross-Genre Discovery**: Can recommend content from genres the user hasn't explicitly chosen but may enjoy based on psychological traits
5. **Progressive Enhancement**: Delivers more refined matches as users complete more surveys

## Future Enhancements

Planned enhancements to the recommendation system include:

1. **Content Feature Analysis**: Incorporating more detailed content attributes beyond genres
2. **Cultural Context Mapping**: Accounting for cultural preferences and backgrounds
3. **Viewing Context**: Considering a user's mood and viewing context
4. **Time-Based Adjustments**: Learning from changes in user ratings over time
5. **Hybrid Approach**: Combining traditional and AI approaches for optimal results 
