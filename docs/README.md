# Cinematch Documentation

This directory contains documentation for various aspects of the Cinematch application.

## Fetcher Service Documentation

The application uses a dual-runtime architecture with a separate fetcher service for memory-intensive background jobs. The following documentation is available:

1. [Fetcher Service Setup Guide](fetcher_service_setup.md) - Overview of the architecture and deployment process for the fetcher service.

2. [Fetcher Service Guide](fetcher_service.md) - Technical troubleshooting guide with detailed information about the fetcher service, how it works, and how to debug issues.

## JRuby Service Documentation (Legacy)

The application previously used a dual-runtime architecture with a separate JRuby service for memory-intensive background jobs, which has been replaced by the fetcher service. The following documentation is kept for reference:

1. [JRuby Render Setup Guide](jruby_render_setup.md) - Overview of the architecture, deployment process, and rationale behind using JRuby for memory-intensive jobs.

2. [JRuby Service Guide](jruby_service.md) - Technical troubleshooting guide with detailed information about the JRuby service, how it works, and how to debug issues.

## Using the Documentation

- If you're new to the fetcher service or need to understand the overall architecture, start with the [Fetcher Service Setup Guide](fetcher_service_setup.md).
- If you're experiencing issues with the fetcher service or need to debug job routing problems, refer to the [Fetcher Service Guide](fetcher_service.md).
- If you're working with legacy code that references the JRuby service, refer to the JRuby service documentation for context. 
