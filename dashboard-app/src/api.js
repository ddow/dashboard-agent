import axios from "axios";

const api = axios.create({
  baseURL: "http://127.0.0.1:8000", // 🔥 local FastAPI backend
  timeout: 5000,
});

export default api;
