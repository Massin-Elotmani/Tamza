<script setup lang="ts">
import { RouterLink, RouterView } from 'vue-router'
</script>

<template>
  <header>
        <RouterLink to="/record">Record 🥺</RouterLink>
        <RouterLink to="/">Home 🤔</RouterLink>
  </header>

  <RouterView />
</template>

<style scoped>

</style>
