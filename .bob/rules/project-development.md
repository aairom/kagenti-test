## Project Development Rule

When working with projects:

1. **Project Contexct Guide**: Always check the links provided here to access the source code repositories for implementation:
   - Kagenti project: https://github.com/kagenti
   - Kagenti repository: https://github.com/kagenti/kagenti
   - Kagenti Agent Development Kit (ADK): https://github.com/kagenti/adk
   - Kagenti operator: https://github.com/kagenti/kagenti-operator
   - Kagenti Agent Examples: https://github.com/kagenti/agent-examples 
   - Kagenti A2A Control Plane: https://github.com/kagenti/agentic-control-plane
2. **Project Structure**: Follow these conventions:
   - The documents of the project should be created in "Docs" folder except readme.md
   - Always provide a Mermaid flow architecture for the project in the "Architecture.md" file
   - All the BASH scripts if needed, should be written in "scripts" folder
   - All the input documents are to be found in "input" folder
   - All the documents in "input" folder should be processed recurssively.
   - All the output documents which are asked to be provided should be writen in timestamped format in "output" folder
   - The result documents should be written in "output" folder, if the "output" folder does not exist, it should be created
   - Always provide README.md with architecture + workflow diagrams as described
   - Always provide a ".gitignore" file which filters/ignores any ".env" files or any folders whichs' names start with "_" (underscore) to be pushed to GitHub (e.g.: _sources/, _images/, _docs/... )
3. **Key Patterns**:
   - Always test the functionnality of the code you provide 
   - When you make updates/enhancements and/or correct the bugs, update the existing documents and scripts, don't create new ones
   - Always provide a virtual environment for Python applications.
4. **Misc**:
   - On a MacOS platform, don't use the port 5000, it is reserved for the "AirDrop" application