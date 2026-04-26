package main

import (
	"context"

	"google.golang.org/grpc"
	"google.golang.org/protobuf/runtime/protoimpl"
)

// ── Auth proto types (inlined — avoids cross-module dependency) ──

type LoginRequest struct {
	state    protoimpl.MessageState
	Email    string `protobuf:"bytes,1,opt,name=email,proto3"`
	Password string `protobuf:"bytes,2,opt,name=password,proto3"`
}

func (x *LoginRequest) Reset()         { *x = LoginRequest{} }
func (x *LoginRequest) String() string { return x.Email }
func (x *LoginRequest) ProtoMessage()  {}

type LoginResponse struct {
	state  protoimpl.MessageState
	Token  string `protobuf:"bytes,1,opt,name=token,proto3"`
	UserId string `protobuf:"bytes,2,opt,name=user_id,proto3,json=userId"`
}

func (x *LoginResponse) Reset()            { *x = LoginResponse{} }
func (x *LoginResponse) String() string    { return x.Token }
func (x *LoginResponse) ProtoMessage()     {}
func (x *LoginResponse) GetToken() string  { return x.Token }
func (x *LoginResponse) GetUserId() string { return x.UserId }

type RegisterRequest struct {
	state    protoimpl.MessageState
	Email    string `protobuf:"bytes,1,opt,name=email,proto3"`
	Password string `protobuf:"bytes,2,opt,name=password,proto3"`
}

func (x *RegisterRequest) Reset()         { *x = RegisterRequest{} }
func (x *RegisterRequest) String() string { return x.Email }
func (x *RegisterRequest) ProtoMessage()  {}

type RegisterResponse struct {
	state  protoimpl.MessageState
	UserId string `protobuf:"bytes,1,opt,name=user_id,proto3,json=userId"`
}

func (x *RegisterResponse) Reset()            { *x = RegisterResponse{} }
func (x *RegisterResponse) String() string    { return x.UserId }
func (x *RegisterResponse) ProtoMessage()     {}
func (x *RegisterResponse) GetUserId() string { return x.UserId }

// ── gRPC client (matches auth.proto service definition) ──────────

type AuthServiceClient interface {
	Login(ctx context.Context, in *LoginRequest, opts ...grpc.CallOption) (*LoginResponse, error)
	Register(ctx context.Context, in *RegisterRequest, opts ...grpc.CallOption) (*RegisterResponse, error)
}

type authServiceClient struct{ cc grpc.ClientConnInterface }

func NewAuthServiceClient(cc grpc.ClientConnInterface) AuthServiceClient {
	return &authServiceClient{cc}
}

func (c *authServiceClient) Login(ctx context.Context, in *LoginRequest, opts ...grpc.CallOption) (*LoginResponse, error) {
	out := new(LoginResponse)
	err := c.cc.Invoke(ctx, "/auth.AuthService/Login", in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}

func (c *authServiceClient) Register(ctx context.Context, in *RegisterRequest, opts ...grpc.CallOption) (*RegisterResponse, error) {
	out := new(RegisterResponse)
	err := c.cc.Invoke(ctx, "/auth.AuthService/Register", in, out, opts...)
	if err != nil {
		return nil, err
	}
	return out, nil
}
