package com.aisherpa.app.data.api

import com.aisherpa.app.data.model.KvmHealthResponse
import com.aisherpa.app.data.model.KvmPowerRequest
import com.aisherpa.app.data.model.KvmSnapshotResponse
import com.aisherpa.app.data.model.KvmTargetsResponse
import com.aisherpa.app.data.model.KvmTaskRequest
import com.aisherpa.app.data.model.KvmTaskResponse
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.Path

interface KvmApiService {

    @GET("/health")
    suspend fun health(): KvmHealthResponse

    @GET("/kvm/targets")
    suspend fun getTargets(
        @Header("Authorization") auth: String
    ): KvmTargetsResponse

    @GET("/kvm/snapshot/{target}")
    suspend fun getSnapshot(
        @Path("target") target: String,
        @Header("Authorization") auth: String
    ): KvmSnapshotResponse

    @GET("/kvm/status/{target}")
    suspend fun getStatus(
        @Path("target") target: String,
        @Header("Authorization") auth: String
    ): Map<String, Any>

    @GET("/kvm/power/{target}")
    suspend fun getPowerStatus(
        @Path("target") target: String,
        @Header("Authorization") auth: String
    ): Map<String, Any>

    @POST("/kvm/power/{target}")
    suspend fun powerAction(
        @Path("target") target: String,
        @Body request: KvmPowerRequest,
        @Header("Authorization") auth: String
    ): Map<String, Any>

    @POST("/kvm/task/{target}")
    suspend fun runTask(
        @Path("target") target: String,
        @Body request: KvmTaskRequest,
        @Header("Authorization") auth: String
    ): KvmTaskResponse
}
