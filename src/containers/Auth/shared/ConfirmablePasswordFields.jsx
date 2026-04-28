import { Form, PasswordField, rawTokens } from '@tetherto/pearpass-lib-ui-kit'

export const ConfirmablePasswordFields = ({
  passwordField,
  confirmPasswordField,
  testID
}) => (
  <Form testID={testID} style={{ gap: rawTokens.spacing12 }}>
    <PasswordField {...passwordField} />
    <PasswordField {...confirmPasswordField} />
  </Form>
)
