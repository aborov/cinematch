document.addEventListener('DOMContentLoaded', function() {
  const animatedElements = document.querySelectorAll('.animated');
  const animationContainers = document.querySelectorAll('.animation_container');

  const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
          if (entry.isIntersecting) {
              const animated = entry.target.querySelector('.animated');
              if (animated) {
                  animated.style.animationPlayState = 'running';
                  animated.style.opacity = '1';
              }
              observer.unobserve(entry.target);
          }
      });
  }, { threshold: 0.1 });

  animationContainers.forEach(container => {
      observer.observe(container);
  });

  animatedElements.forEach(el => {
      el.style.opacity = '0';
      el.style.animationPlayState = 'paused';
  });
});
