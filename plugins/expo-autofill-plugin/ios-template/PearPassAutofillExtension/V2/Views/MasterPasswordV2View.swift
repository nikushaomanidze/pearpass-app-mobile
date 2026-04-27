//
//  MasterPasswordV2View.swift
//  PearPassAutoFillExtension
//
//  V2 master password screen. Mirrors android-template/res/layout/fragment_master_password_v2.xml.
//  Sheet header (logo + close + title) + content card with title/subtitle/password + Continue button.
//

import SwiftUI

struct MasterPasswordV2View: View {

    var headerTitle: String = "Add a passkey"
    @Binding var password: String

    var onClose: () -> Void = {}
    var onContinue: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            PPSheetHeader(
                title: headerTitle,
                showLogo: true,
                showClose: true,
                onClose: onClose
            )

            PPContentCard {
                VStack(spacing: 0) {
                    // Body
                    VStack(spacing: 0) {
                        Text("Enter Your Master Password")
                            .font(PPTypography.title)
                            .foregroundColor(PPColors.textPrimary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, PPSpacing.s16)

                        Text("Please enter your master password to continue")
                            .font(PPTypography.label)
                            .foregroundColor(PPColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, PPSpacing.s8)

                        Spacer().frame(height: 46)

                        PPPasswordField(
                            label: "Password",
                            text: $password,
                            placeholder: "Enter Master Password"
                        )

                        Spacer()
                    }
                    .padding(.horizontal, PPSpacing.s16)
                    .padding(.top, PPSpacing.s24)

                    // Top border for footer
                    Rectangle()
                        .fill(PPColors.borderPrimary)
                        .frame(height: 1)

                    // Continue button
                    PPButton(title: "Continue", variant: .primary, action: onContinue)
                        .padding(.horizontal, PPSpacing.s16)
                        .padding(.top, PPSpacing.s16)
                        .padding(.bottom, PPSpacing.s12)
                }
            }
        }
    }
}
