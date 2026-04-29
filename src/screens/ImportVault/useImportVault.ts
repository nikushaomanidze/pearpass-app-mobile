import { useState, useCallback } from 'react'

import { useLingui } from '@lingui/react/macro'
import { usePair, useVault } from '@tetherto/pearpass-lib-vault'
import { Platform } from 'react-native'

type ImportVaultState = {
  isLoading: boolean
  error: string
  isPaired: boolean
}

export const useImportVault = () => {
  const { t } = useLingui()
  const [state, setState] = useState<ImportVaultState>({
    isLoading: false,
    error: '',
    isPaired: false
  })

  const { refetch: refetchVault, addDevice } = useVault()
  const {
    pairActiveVault,
    cancelPairActiveVault,
    isLoading: isPairing
  } = usePair()

  const pairWithCode = useCallback(
    async (code: string) => {
      try {
        setState((prev) => ({ ...prev, error: '', isLoading: true }))
        const vaultId = await pairActiveVault(code)
        await refetchVault(vaultId)
        await addDevice(Platform.OS + ' ' + Platform.Version)
        setState((prev) => ({ ...prev, isLoading: false, isPaired: true }))
        return true
      } catch {
        setState((prev) => ({
          ...prev,
          isLoading: false,
          error: t`Something went wrong, please check invite code`
        }))
        return false
      }
    },
    [pairActiveVault, refetchVault, addDevice]
  )

  const cancelPairing = useCallback(async () => {
    await cancelPairActiveVault()
    setState({ isLoading: false, error: '', isPaired: false })
  }, [cancelPairActiveVault])

  return {
    isLoading: state.isLoading || isPairing,
    error: state.error,
    isPaired: state.isPaired,
    pairWithCode,
    cancelPairing
  }
}
