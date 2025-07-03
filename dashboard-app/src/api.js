const API_URL = "http://127.0.0.1:8000";

export async function login(email, password) {
  const response = await fetch(`${API_URL}/login`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      username: email,
      password: password
    })
  });
  if (!response.ok) {
    throw new Error("Login failed");
  }
  return response.json();
}

export async function fetchDashboard(token) {
  const response = await fetch(`${API_URL}/dashboard`, {
    headers: { Authorization: `Bearer ${token}` }
  });
  if (!response.ok) {
    throw new Error("Unauthorized");
  }
  return response.json();
}
