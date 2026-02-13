# mittwald AI Developer Tools

This repository contains developer tools that help teams work faster with AI hosted by [mittwald](https://www.mittwald.de/mstudio/ai-hosting) in Germany.

mittwald AI hosting is especially useful for developer workflows that need:
- short feedback loops during coding
- reliable automation for continuous integration
- GDPR-aware, Germany-hosted infrastructure for AI-assisted development

## Generate Commit Messages

AI-powered, well-formed git commit message generation based on your staged changes.

### Why this helps

Good commit messages are important but easy to postpone. AI-assisted generation helps you:
- keep commit history understandable and review-friendly
- consistentely follow the [Conventional Commits](https://www.conventionalcommits.org/) format
- reduce time spent writing commit text
- improve consistency across contributors

### What the installer does

The installer script sets up and configures `cmai` so commit messages can be generated using mittwald AI.

### Quick install

```bash
curl -fsSL https://github.com/mittwald/ai-developer-tools/raw/refs/heads/main/install-git-commit-ai.sh | bash
```

### Typical workflow

1. Stage your changes (`git add ...`).
2. Commit your changes, ommitting the commit message (`git commit`).
3. `cmai` uses mittwald AI to generate a commit message.
4. Review and adjust the message if needed in your editor.
5. 🥳

## More tools coming soon

This repository is intended as a collection point for developer productivity tooling around mittwald AI hosting.

Check back later.

## Feedback

Please use this project's [issue tracker](https://github.com/mittwald/ai-developer-tools/issues) to report specific suggestions or issues.

For security-related issues, please refrain from using the public issue tracker or discussion board. Have a look at the [security policy](./SECURITY.md), instead.

Also, please note that the issue tracker is not a support channel for mittwald's hosting products. Please use our regular [support options](https://www.mittwald.de/impressum) to receive product support.

## Contributing

We are happy to accept external contributions to our documentation. See the [Contribution guide](./CONTRIBUTING.md) for more information.
