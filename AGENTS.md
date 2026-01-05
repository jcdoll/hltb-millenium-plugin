# Overview

This project is a [Millennium](https://steambrew.app/) plugin that displays [How Long To Beat](https://howlongtobeat.com/) completion time data on game pages in the Steam library.

## Always rebuild after frontend changes
- The agent should always rebuild via `npm run build` after every frontend change

## If unsure or stuck ask the user
- If the user asks you to do something and it fails, do not silently move on. Ask the user for help.
- If you are unsure about what to do or the user requirements are unclear ask for clarification.

## Always plan first
- Typical workflow: user makes a request, you formulate a plan, you share the plan for approval. If approved you implement the plan.
- NEVER assume that presenting a good plan means you should implement it. Request approval.

## Documentation Standards
- Do not use excessive bold in markdown documents. Only use font styling selectively.
- Do not use emojis in either code or docs.
- Do not include "last updated" dates for documentation or code.

## Code quality
- IMPORTANT: Maintain clean, readable code without legacy baggage. For example, when refactoring delete the old interface instead of adding thin wrappers.
