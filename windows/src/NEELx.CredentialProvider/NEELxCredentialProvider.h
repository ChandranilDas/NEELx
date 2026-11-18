#pragma once

// NEELx Windows 11 Lock Screen Credential Provider Contract (WinLogon ICredentialProvider)
// Bridges native Windows 11 Lock Screen tiles with NEELx.App's local DirectML 3D verifier
// over an ACL-hardened named pipe restricted to SYSTEM and the interactive user SID.

#include <windows.h>
#include <credentialprovider.h>

// {9F4D7B21-6C1E-4A3E-8D25-E8477B14A902}
static const GUID CLSID_NEELxCredentialProvider =
{ 0x9f4d7b21, 0x6c1e, 0x4a3e, { 0x8d, 0x25, 0xe8, 0x47, 0x7b, 0x14, 0xa9, 0x02 } };

static constexpr wchar_t kNEELxUnlockPipeName[] = L"\\\\.\\pipe\\NEELxBiometricUnlock";

class NEELxCredentialProvider : public ICredentialProvider
{
public:
    virtual HRESULT STDMETHODCALLTYPE SetUsageScenario(
        CREDENTIAL_PROVIDER_USAGE_SCENARIO cpus,
        DWORD dwFlags) override = 0;

    virtual HRESULT STDMETHODCALLTYPE Advise(
        ICredentialProviderEvents* pcpe,
        UINT_PTR upAdviseContext) override = 0;

    virtual HRESULT STDMETHODCALLTYPE UnAdvise() override = 0;
    virtual HRESULT STDMETHODCALLTYPE GetFieldDescriptorCount(DWORD* pdwCount) override = 0;
    virtual HRESULT STDMETHODCALLTYPE GetCredentialCount(
        DWORD* pdwCount,
        DWORD* pdwDefault,
        BOOL* pbAutoLogonWithDefault) override = 0;
};
