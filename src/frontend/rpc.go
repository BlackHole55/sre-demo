// Copyright 2018 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"context"

	pb "github.com/GoogleCloudPlatform/microservices-demo/src/frontend/genproto"
)

const (
	avoidNoopCurrencyConversionRPC = false
)

func (fe *frontendServer) getCurrencies(ctx context.Context) ([]string, error) {
	if fe.currencySvcConn == nil {
		return []string{"USD", "EUR", "GBP", "JPY", "CAD", "TRY"}, nil
	}
	currs, err := pb.NewCurrencyServiceClient(fe.currencySvcConn).
		GetSupportedCurrencies(ctx, &pb.Empty{})
	if err != nil {
		return nil, err
	}
	return currs.CurrencyCodes, nil
}

func (fe *frontendServer) getProducts(ctx context.Context) ([]*pb.Product, error) {
	resp, err := pb.NewProductCatalogServiceClient(fe.productCatalogSvcConn).
		ListProducts(ctx, &pb.Empty{})
	return resp.GetProducts(), err
}

func (fe *frontendServer) getProduct(ctx context.Context, id string) (*pb.Product, error) {
	resp, err := pb.NewProductCatalogServiceClient(fe.productCatalogSvcConn).
		GetProduct(ctx, &pb.GetProductRequest{Id: id})
	return resp, err
}

func (fe *frontendServer) getCart(ctx context.Context, userID string) ([]*pb.CartItem, error) {
	if fe.cartSvcConn == nil {
		return []*pb.CartItem{}, nil
	}
	cart, err := pb.NewCartServiceClient(fe.cartSvcConn).
		GetCart(ctx, &pb.GetCartRequest{UserId: userID})
	if err != nil {
		return nil, err
	}
	return cart.GetItems(), nil
}

func (fe *frontendServer) emptyCart(ctx context.Context, userID string) error {
	if fe.cartSvcConn == nil {
		return nil
	}
	_, err := pb.NewCartServiceClient(fe.cartSvcConn).
		EmptyCart(ctx, &pb.EmptyCartRequest{UserId: userID})
	return err
}

func (fe *frontendServer) insertCart(ctx context.Context, userID, productID string, quantity int32) error {
	if fe.cartSvcConn == nil {
		return nil // silently drop — no cart service
	}
	_, err := pb.NewCartServiceClient(fe.cartSvcConn).
		AddItem(ctx, &pb.AddItemRequest{
			UserId: userID,
			Item:   &pb.CartItem{ProductId: productID, Quantity: quantity},
		})
	return err
}

func (fe *frontendServer) convertCurrency(ctx context.Context, money *pb.Money, currency string) (*pb.Money, error) {
	if fe.currencySvcConn == nil || currency == "" || currency == money.GetCurrencyCode() {
		// return original price unchanged
		return money, nil
	}
	return pb.NewCurrencyServiceClient(fe.currencySvcConn).
		Convert(ctx, &pb.CurrencyConversionRequest{
			From:   money,
			ToCode: currency,
		})
}

func (fe *frontendServer) getShippingQuote(ctx context.Context, items []*pb.CartItem, currency string) (*pb.Money, error) {
	if fe.shippingSvcConn == nil {
		return &pb.Money{CurrencyCode: currency, Units: 0, Nanos: 0}, nil
	}
	quote, err := pb.NewShippingServiceClient(fe.shippingSvcConn).
		GetQuote(ctx, &pb.GetQuoteRequest{Items: items})
	if err != nil {
		return nil, err
	}
	localized, err := fe.convertCurrency(ctx, quote.GetCostUsd(), currency)
	if err != nil {
		return nil, err
	}
	return localized, nil
}

func (fe *frontendServer) getRecommendations(ctx context.Context, userID string, productIDs []string) ([]*pb.Product, error) {
	if fe.recommendationSvcConn == nil {
		return []*pb.Product{}, nil
	}
	resp, err := pb.NewRecommendationServiceClient(fe.recommendationSvcConn).
		ListRecommendations(ctx, &pb.ListRecommendationsRequest{
			UserId:     userID,
			ProductIds: productIDs,
		})
	if err != nil {
		return nil, err
	}
	out := make([]*pb.Product, len(resp.GetProductIds()))
	for i, id := range resp.GetProductIds() {
		p, err := fe.getProduct(ctx, id)
		if err != nil {
			return nil, err
		}
		out[i] = p
	}
	return out, nil
}

func (fe *frontendServer) getAd(ctx context.Context, ctxKeys []string) ([]*pb.Ad, error) {
	if fe.adSvcConn == nil {
		return []*pb.Ad{}, nil
	}
	resp, err := pb.NewAdServiceClient(fe.adSvcConn).GetAds(ctx,
		&pb.AdRequest{ContextKeys: ctxKeys})
	if err != nil {
		return nil, err
	}
	return resp.GetAds(), nil
}
