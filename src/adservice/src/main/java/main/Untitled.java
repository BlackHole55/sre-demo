package main

import (
    "context"
    "crypto/rand"
    "encoding/hex"
    "fmt"
    "net"
    "os"
    "time"

    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/sirupsen/logrus"
    "google.golang.org/grpc"
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/health"
    healthpb "google.golang.org/grpc/health/grpc_health_v1"
    "google.golang.org/grpc/status"

    pb "github.com/GoogleCloudPlatform/microservices-demo/src/authservice/genproto"
)

var log = logrus.New()

type authService struct {
    pb.UnimplementedAuthServiceServer
    db *pgxpool.Pool
}

func main() {
    port := os.Getenv("PORT")
    if port == "" {
        port = "9555"
    }

    dsn := os.Getenv("POSTGRES_DSN")
    if dsn == "" {
        log.Fatal("POSTGRES_DSN not set")
    }

    cfg, err := pgxpool.ParseConfig(dsn)
    if err != nil {
        log.Fatalf("failed to parse DSN: %v", err)
    }
    cfg.ConnConfig.RuntimeParams["search_path"] = "auth"

    pool, err := pgxpool.NewWithConfig(context.Background(), cfg)
    if err != nil {
        log.Fatalf("failed to connect to postgres: %v", err)
    }
    defer pool.Close()

    if err := pool.Ping(context.Background()); err != nil {
        log.Fatalf("postgres ping failed: %v", err)
    }
    log.Info("connected to postgres (auth schema)")

    lis, err := net.Listen("tcp", fmt.Sprintf(":%s", port))
    if err != nil {
        log.Fatal(err)
    }

    srv := grpc.NewServer()
    pb.RegisterAuthServiceServer(srv, &authService{db: pool})
    healthcheck := health.NewServer()
    healthpb.RegisterHealthServer(srv, healthcheck)

    log.Infof("authservice listening on :%s", port)
    if err := srv.Serve(lis); err != nil {
        log.Fatal(err)
    }
}

// Register creates a new user
func (s *authService) Register(ctx context.Context, req *pb.RegisterRequest) (*pb.RegisterResponse, error) {
    if req.Email == "" || req.Password == "" {
        return nil, status.Error(codes.InvalidArgument, "email and password required")
    }
    userID := generateID()
    // store plain hash for demo — use bcrypt in production
    _, err := s.db.Exec(ctx,
        `INSERT INTO users (id, email, password_hash) VALUES ($1, $2, $3)`,
        userID, req.Email, req.Password)
    if err != nil {
        return nil, status.Errorf(codes.AlreadyExists, "user already exists: %v", err)
    }
    log.Infof("registered user %q", req.Email)
    return &pb.RegisterResponse{UserId: userID}, nil
}

// Login validates credentials and returns a session token
func (s *authService) Login(ctx context.Context, req *pb.LoginRequest) (*pb.LoginResponse, error) {
    var userID, hash string
    err := s.db.QueryRow(ctx,
        `SELECT id, password_hash FROM users WHERE email = $1`, req.Email).
        Scan(&userID, &hash)
    if err != nil {
        return nil, status.Error(codes.Unauthenticated, "invalid credentials")
    }
    if hash != req.Password {
        return nil, status.Error(codes.Unauthenticated, "invalid credentials")
    }

    token := generateID()
    _, err = s.db.Exec(ctx,
        `INSERT INTO sessions (token, user_id, expires_at)
         VALUES ($1, $2, $3)`,
        token, userID, time.Now().Add(24*time.Hour))
    if err != nil {
        return nil, status.Errorf(codes.Internal, "failed to create session: %v", err)
    }
    log.Infof("login ok for %q", req.Email)
    return &pb.LoginResponse{Token: token, UserId: userID}, nil
}

// ValidateSession checks a token and returns the user ID
func (s *authService) ValidateSession(ctx context.Context, req *pb.ValidateSessionRequest) (*pb.ValidateSessionResponse, error) {
    var userID string
    err := s.db.QueryRow(ctx,
        `SELECT user_id FROM sessions
         WHERE token = $1 AND expires_at > now()`, req.Token).
        Scan(&userID)
    if err != nil {
        return &pb.ValidateSessionResponse{Valid: false}, nil
    }
    return &pb.ValidateSessionResponse{Valid: true, UserId: userID}, nil
}

func generateID() string {
    b := make([]byte, 16)
    rand.Read(b)
    return hex.EncodeToString(b)
}