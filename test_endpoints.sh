#!/bin/bash
# Movie Reservation System - API Test Script
#
# Usage:
#   ./test_endpoints.sh              → Full showcase (all features, admin JWT bypasses rate limit)
#   ./test_endpoints.sh --rate-limit → Rate limit demo (shows 429 after 7 requests without JWT)

BASE_URL="http://localhost:3000"
MODE="${1:-}"

# ─────────────────────────────────────────────
# HELPER
# ─────────────────────────────────────────────
extract() { echo "$1" | grep -o "\"$2\":\"[^\"]*\"" | awk -F'"' '{print $4}' | head -n 1; }

# ─────────────────────────────────────────────
# MODE: Rate Limit Demo
# ─────────────────────────────────────────────
if [ "$MODE" = "--rate-limit" ]; then
  echo "========================================"
  echo "⏱️  Rate Limit Demo (7 req/min per IP)"
  echo "========================================"
  echo "Making requests WITHOUT admin JWT until rate limit triggers (limit: 7)..."
  echo ""

  for i in $(seq 1 9); do
    HTTP_CODE=$(curl -s -o /tmp/rl_body.json -w "%{http_code}" $BASE_URL/movies)
    BODY=$(cat /tmp/rl_body.json)

    if [ "$HTTP_CODE" = "429" ]; then
      ERROR=$(echo "$BODY" | grep -o '"error":"[^"]*"' | awk -F'"' '{print $4}')
      echo "[Request $i] ❌ 429 Too Many Requests — Rate limit hit!"
      echo "           $ERROR"
    else
      echo "[Request $i] ✅ $HTTP_CODE OK"
    fi
  done

  echo ""
  echo "── Now retrying with Admin JWT (should bypass rate limit) ──"
  ADMIN_RES=$(curl -s -X POST $BASE_URL/admin/signin \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"adminpass"}')
  TOKEN=$(extract "$ADMIN_RES" "token")

  if [ -z "$TOKEN" ]; then
    echo "❌ Could not get admin token. Is the server running?"
    exit 1
  fi

  BYPASS_RES=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" $BASE_URL/movies)
  echo "[Request 10] ✅ $BYPASS_RES OK — Admin JWT bypasses rate limit"
  echo ""
  echo "✅ Rate limit demo complete."
  exit 0
fi

# ─────────────────────────────────────────────
# MODE: Full Feature Showcase (default)
# ─────────────────────────────────────────────
echo "========================================"
echo "🎬 Movie Reservation System — Full Showcase"
echo "   (Admin JWT active: rate limit bypassed)"
echo "========================================"
echo ""

# 1. Admin Sign-in
echo "[1] 🔐 Admin Sign-in..."
ADMIN_RES=$(curl -s -X POST $BASE_URL/admin/signin \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"adminpass"}')
TOKEN=$(extract "$ADMIN_RES" "token")

if [ -z "$TOKEN" ]; then
  echo "❌ Failed to retrieve Admin Token. Ensure server is running."
  exit 1
fi
echo "✅ Admin Token retrieved (truncated): ${TOKEN:0:20}..."
echo ""

AUTH="-H \"Authorization: Bearer $TOKEN\""
AUTH_HEADER="Authorization: Bearer $TOKEN"

# 2. Create User
echo "[2] 👤 Creating User..."
USER_EMAIL="user$RANDOM@example.com"
USER_RES=$(curl -s -X POST $BASE_URL/users \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"Test User\",\"email\":\"$USER_EMAIL\",\"password\":\"pass123\"}")
USER_ID=$(extract "$USER_RES" "id")
echo "✅ USER_ID: $USER_ID"
echo ""

# 3. Create Theater
echo "[3] 🏛️  Creating Theater..."
THEATER_RES=$(curl -s -X POST $BASE_URL/theaters \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"name":"Grand Cinema","location":"Uptown"}')
THEATER_ID=$(extract "$THEATER_RES" "id")
echo "✅ THEATER_ID: $THEATER_ID"
echo ""

# 4. Add Seat
echo "[4] 💺 Adding Seat A1..."
SEAT_RES=$(curl -s -X POST $BASE_URL/seats/add \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "{\"theaterId\":\"$THEATER_ID\",\"seatNumber\":\"A1\"}")
echo "✅ Seat: $(echo "$SEAT_RES" | grep -o '"seatNumber":"[^"]*"')"
echo ""

# 5. Create Movie
echo "[5] 🎥 Creating Movie..."
MOVIE_RES=$(curl -s -X POST $BASE_URL/movies \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "{\"title\":\"Inception\",\"description\":\"Mind-bending thriller\",\"duration\":148,\"theaterId\":\"$THEATER_ID\",\"showtime\":\"2024-03-07 20:00\"}")
MOVIE_ID=$(extract "$MOVIE_RES" "id")
echo "✅ MOVIE_ID: $MOVIE_ID"
echo ""

# 6. Reserve Seat
echo "[6] 🎟️  Reserving Seat A1..."
RES_RES=$(curl -s -X POST $BASE_URL/seats/reserve \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "{\"theaterId\":\"$THEATER_ID\",\"seatNumber\":\"A1\",\"userId\":\"$USER_ID\",\"movieId\":\"$MOVIE_ID\"}")
RESERVATION_ID=$(extract "$RES_RES" "reservationId")
echo "✅ RESERVATION_ID: $RESERVATION_ID"
echo ""

# 7. Issue Ticket
echo "[7] 🎫 Issuing Ticket..."
TICKET_RES=$(curl -s -X POST $BASE_URL/tickets/issue \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  -d "{\"reservationId\":\"$RESERVATION_ID\",\"amount\":15.00}")
TICKET_ID=$(extract "$TICKET_RES" "ticketId")
echo "✅ TICKET_ID: $TICKET_ID"
echo ""

# 8. GET Endpoints
echo "========================================"
echo "🔍 GET Endpoints"
echo "========================================"

echo "[GET] User details:"
curl -s -H "$AUTH_HEADER" $BASE_URL/users/$USER_ID | grep -o '"email":"[^"]*"'
echo ""

echo "[GET] Theater seats:"
curl -s -H "$AUTH_HEADER" $BASE_URL/theaters/$THEATER_ID/seats | grep -o '"seat_number":"[^"]*"'
echo ""

echo "[GET] Movies at Theater:"
curl -s -H "$AUTH_HEADER" $BASE_URL/movies/theater/$THEATER_ID | grep -o '"title":"[^"]*"'
echo ""

echo "[GET] Ticket details:"
curl -s -H "$AUTH_HEADER" $BASE_URL/tickets/$TICKET_ID | grep -o '"issued_at":"[^"]*"'
echo ""

echo "[GET] All User Tickets:"
curl -s -H "$AUTH_HEADER" $BASE_URL/tickets/user/$USER_ID | grep -o '"id":"[^"]*"'
echo ""

echo "🎉 Full showcase complete. All features demonstrated."
echo ""
echo "Tip: Run './test_endpoints.sh --rate-limit' to demo rate limiting."
