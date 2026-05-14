package hipstershop

// Auth service types — matches src/authservice/genproto/auth.proto

type LoginRequest struct {
	Email    string `protobuf:"bytes,1,opt,name=email"`
	Password string `protobuf:"bytes,2,opt,name=password"`
}

func (x *LoginRequest) Reset()         {}
func (x *LoginRequest) String() string { return x.Email }
func (x *LoginRequest) ProtoMessage()  {}

type LoginResponse struct {
	Token  string `protobuf:"bytes,1,opt,name=token"`
	UserId string `protobuf:"bytes,2,opt,name=user_id"`
}

func (x *LoginResponse) Reset()            {}
func (x *LoginResponse) String() string    { return x.Token }
func (x *LoginResponse) ProtoMessage()     {}
func (x *LoginResponse) GetToken() string  { return x.Token }
func (x *LoginResponse) GetUserId() string { return x.UserId }

type RegisterRequest struct {
	Email    string `protobuf:"bytes,1,opt,name=email"`
	Password string `protobuf:"bytes,2,opt,name=password"`
}

func (x *RegisterRequest) Reset()         {}
func (x *RegisterRequest) String() string { return x.Email }
func (x *RegisterRequest) ProtoMessage()  {}

type RegisterResponse struct {
	UserId string `protobuf:"bytes,1,opt,name=user_id"`
}

func (x *RegisterResponse) Reset()         {}
func (x *RegisterResponse) String() string { return x.UserId }
func (x *RegisterResponse) ProtoMessage()  {}
