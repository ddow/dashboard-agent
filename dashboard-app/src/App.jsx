import React, { useState, useEffect } from "react";
import { initializeApp } from "firebase/app";
import {
  getAuth,
  signInWithEmailAndPassword,
  onAuthStateChanged,
  multiFactor,
} from "firebase/auth";

const firebaseConfig = {
  apiKey: "AIzaSyDxxxxxxx-your-key",
  authDomain: "dashboard-danieldow.firebaseapp.com",
  projectId: "dashboard-danieldow",
  storageBucket: "dashboard-danieldow.appspot.com",
  messagingSenderId: "1234567890",
  appId: "1:1234567890:web:abc123def456",
};

initializeApp(firebaseConfig);
const auth = getAuth();

export default function DashboardApp() {
  const [user, setUser] = useState(null);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    onAuthStateChanged(auth, (u) => {
      if (u) {
        setUser(u);
      } else {
        setUser(null);
      }
    });
  }, []);

  const handleLogin = async (e) => {
    e.preventDefault();
    setError("");
    try {
      const cred = await signInWithEmailAndPassword(auth, email, password);
      if (multiFactor(cred.user).enrolledFactors.length > 0) {
        alert("Multi-factor authentication required. Please use your device.");
      }
    } catch (err) {
      setError(err.message);
    }
  };

  const handleLogout = () => {
    auth.signOut();
  };

  if (!user) {
    return (
      <div className="flex items-center justify-center h-screen bg-gray-50">
        <form
          onSubmit={handleLogin}
          className="bg-white shadow-xl rounded-xl p-8 space-y-4 w-96"
        >
          <h1 className="text-2xl font-bold text-center">🔒 Dashboard Login</h1>
          {error && <p className="text-red-500">{error}</p>}
          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="w-full border p-2 rounded-lg"
            required
          />
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full border p-2 rounded-lg"
            required
          />
          <button
            type="submit"
            className="w-full bg-blue-600 text-white p-2 rounded-lg hover:bg-blue-700"
          >
            Login
          </button>
        </form>
      </div>
    );
  }

  return (
    <div className="p-8 space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-3xl font-bold">
          👋 Welcome, {user.email === "strngr12@gmail.com" ? "Daniel" : "Kristan"}
        </h1>
        <button
          onClick={handleLogout}
          className="bg-red-500 text-white px-4 py-2 rounded-lg hover:bg-red-600"
        >
          Logout
        </button>
      </div>

      {user.email === "strngr12@gmail.com" && (
        <div className="space-y-4">
          <h2 className="text-xl font-semibold">🖥️ Daniel’s Projects</h2>
          <div className="grid grid-cols-1 gap-4">
            <div className="p-4 rounded-xl shadow border bg-white">
              <h3 className="font-bold">Fast Train Tickets</h3>
              <p>Status: Deployed & live</p>
            </div>
            <div className="p-4 rounded-xl shadow border bg-white">
              <h3 className="font-bold">Ethical Affiliate Website</h3>
              <p>Status: In planning</p>
            </div>
            <div className="p-4 rounded-xl shadow border bg-white">
              <h3 className="font-bold">Diagnosing Elijah (Book)</h3>
              <p>Status: Outline + draft in progress</p>
            </div>
          </div>
        </div>
      )}

      {user.email === "kristan.anderson@gmail.com" && (
        <div className="space-y-4">
          <h2 className="text-xl font-semibold">📖 Kristan’s Projects</h2>
          <div className="p-4 rounded-xl shadow border bg-white">
            <h3 className="font-bold">Diagnosing Elijah (Book)</h3>
            <p>Status: Outline + draft in progress</p>
          </div>
        </div>
      )}
    </div>
  );
}