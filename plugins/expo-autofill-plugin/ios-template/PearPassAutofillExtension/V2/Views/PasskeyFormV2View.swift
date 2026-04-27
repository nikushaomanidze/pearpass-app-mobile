//
//  PasskeyFormV2View.swift
//  PearPassAutoFillExtension
//
//  V2 passkey form screen. Mirrors android-template/res/layout/fragment_passkey_form_v2.xml.
//  Sheet header (back + close + "Create Passkey") + scrollable form + bottom buttons.
//

import SwiftUI

struct PasskeyFormV2View: View {

    var headerTitle: String = "Create Passkey"

    @Binding var titleText: String
    @Binding var username: String
    @Binding var passkeyDate: String
    @Binding var website: String
    @Binding var comment: String
    var folderName: String?

    var titleError: String? = nil
    var websiteError: String? = nil
    var saveError: String? = nil
    /// Disables Save/Discard while the passkey is being generated and the
    /// ADD/UPDATE job is being written so the user cannot fire the save
    /// twice or dismiss mid-flight.
    var isSaving: Bool = false

    var onBack: () -> Void = {}
    var onClose: () -> Void = {}
    var onSelectFolder: () -> Void = {}
    var onSave: () -> Void = {}
    var onDiscard: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            PPSheetHeaderBack(
                title: headerTitle,
                onBack: onBack,
                onClose: onClose
            )

            PPContentCard {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Title
                            PPInputField(
                                label: "Title",
                                text: $titleText,
                                placeholder: "Title"
                            )

                            if let titleError = titleError {
                                Text(titleError)
                                    .font(PPTypography.caption)
                                    .foregroundColor(PPColors.surfaceError)
                                    .padding(.top, PPSpacing.s4)
                            }

                            // Section: Credentials
                            sectionHeader("Credentials")
                                .padding(.top, PPSpacing.s24)
                                .padding(.bottom, PPSpacing.s8)

                            PPInputField(
                                label: "Email or Username",
                                text: $username,
                                placeholder: "Email or Username",
                                keyboardType: .emailAddress
                            )

                            Spacer().frame(height: PPSpacing.s8)

                            PPInputField(
                                label: "Passkey",
                                text: $passkeyDate,
                                placeholder: "Date",
                                isEditable: false
                            )

                            // Section: Details
                            sectionHeader("Details")
                                .padding(.top, PPSpacing.s24)
                                .padding(.bottom, PPSpacing.s8)

                            PPInputField(
                                label: "Website",
                                text: $website,
                                placeholder: "https://...",
                                keyboardType: .URL
                            )

                            if let websiteError = websiteError {
                                Text(websiteError)
                                    .font(PPTypography.caption)
                                    .foregroundColor(PPColors.surfaceError)
                                    .padding(.top, PPSpacing.s4)
                            }

                            Spacer().frame(height: PPSpacing.s8)

                            PPInputField(
                                label: "Comment",
                                text: $comment,
                                placeholder: "Optional"
                            )

                            Spacer().frame(height: PPSpacing.s8)

                            // Folder selector
                            PPListItem(
                                title: folderName ?? "Select folder",
                                leadingIcon: nil,
                                onTap: onSelectFolder
                            )
                        }
                        .padding(PPSpacing.s16)
                    }

                    // Divider
                    Rectangle()
                        .fill(PPColors.borderPrimary)
                        .frame(height: 1)
                        .padding(.horizontal, PPSpacing.s12)

                    // Bottom: error + save + discard
                    VStack(spacing: 0) {
                        if let saveError = saveError {
                            Text(saveError)
                                .font(PPTypography.caption)
                                .foregroundColor(PPColors.surfaceError)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, PPSpacing.s8)
                        }

                        PPButton(
                            title: isSaving ? "Saving..." : "Save & Add Login",
                            variant: .primary,
                            isEnabled: !isSaving,
                            action: onSave
                        )

                        PPButton(
                            title: "Discard",
                            variant: .secondary,
                            isEnabled: !isSaving,
                            action: onDiscard
                        )
                        .padding(.top, PPSpacing.s8)
                    }
                    .padding(.horizontal, PPSpacing.s16)
                    .padding(.top, PPSpacing.s16)
                    .padding(.bottom, PPSpacing.s12)
                }
            }
        }
        .background(PPColors.surfacePrimary)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(PPTypography.label)
            .foregroundColor(PPColors.textSecondary)
    }
}
