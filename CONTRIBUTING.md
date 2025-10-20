# Contributing to Energy Shield

Thank you for your interest in contributing to the Energy Shield project! We welcome contributions from the community.

## Getting Started

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes
4. Test your changes thoroughly
5. Submit a pull request

## Development Guidelines

### Code Formatting

This project uses pre-commit hooks to ensure consistent code formatting. Before making your first commit:

1. Install pre-commit if you haven't already:
   ```bash
   pip install pre-commit
   ```

2. Install the pre-commit hooks:
   ```bash
   pre-commit install
   ```

3. The hooks will automatically run on each commit to format your code

### Shader Development

- Follow Godot's shader conventions
- Add comments for complex shader logic
- Test shaders on both plane and sphere meshes
- Ensure compatibility with different Godot versions

### Documentation

- Update the README.md if adding new features
- Document new shader parameters thoroughly
- Include example usage where applicable

### Testing

- Test your changes in both the editor and exported builds
- Verify web build compatibility for shader changes
- Test on different mesh types when applicable

## Submitting Issues

When reporting bugs or requesting features:

- Use a clear, descriptive title
- Provide steps to reproduce (for bugs)
- Include Godot version and platform information
- Attach screenshots or videos when helpful

## License and Copyright

By contributing to this project, you agree that:

- Your contributions will be licensed under the same MIT License that covers the project
- You have the right to submit your contributions (you own the copyright or have permission)
- Your contributions are your own original work or properly attributed third-party work

All contributions become part of the project and are subject to the project's MIT License terms.

## Questions?

Feel free to open an issue for questions or join the discussion in existing issues.

Thank you for contributing!
