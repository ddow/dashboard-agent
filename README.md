# Dashboard Agent

This repository contains the code for a small React dashboard and supporting deployment scripts.

## Environment Variables

`REACT_APP_API_URL`
: Optional. Specifies the base URL for the backend API used by the React application. When defined during `npm start` or `npm run build`, this value overrides the default URL in `dashboard-app/src/api.js`.

Example:

```bash
REACT_APP_API_URL=https://your-api.example.com npm start
```

If the variable is not provided, the app falls back to the production API URL hard coded in `src/api.js`.

